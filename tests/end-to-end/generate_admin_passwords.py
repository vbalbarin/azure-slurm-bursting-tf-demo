#!/usr/bin/env python3
from __future__ import annotations

import argparse
from collections.abc import Callable, Sequence
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import secrets
import stat
import sys
import tempfile
from typing import NoReturn


EXIT_INPUT = 2
EXIT_PARTIAL = 3
EXIT_POLICY = 4
EXIT_LOCKED = 5
EXIT_PERSISTENCE = 6


@dataclass(frozen=True)
class PasswordPolicy:
    id: str
    length: int
    uppercase_alphabet: str
    lowercase_alphabet: str
    numeric_alphabet: str
    special_alphabet: str
    minimum_per_class: int

    @property
    def alphabets(self) -> tuple[str, str, str, str]:
        return (
            self.uppercase_alphabet,
            self.lowercase_alphabet,
            self.numeric_alphabet,
            self.special_alphabet,
        )

    @property
    def allowed_characters(self) -> str:
        return "".join(self.alphabets)


@dataclass(frozen=True)
class CredentialTarget:
    target: str
    account: str
    secret_name: str


POLICY = PasswordPolicy(
    id="interactive-admin-v1",
    length=16,
    uppercase_alphabet="ABCDEFGHJKLMNPQRSTUVWXYZ",
    lowercase_alphabet="abcdefghijkmnopqrstuvwxyz",
    numeric_alphabet="23456789",
    special_alphabet="!@#$%^*()-_+=",
    minimum_per_class=2,
)

TARGETS = (
    CredentialTarget("windows", "windowsadmin", "windows-admin-password"),
    CredentialTarget("cyclecloud", "hpcadmin", "cyclecloud-admin-password"),
)


class GeneratorError(Exception):
    exit_code = EXIT_PERSISTENCE


class InputError(GeneratorError):
    exit_code = EXIT_INPUT


class PartialSetError(GeneratorError):
    exit_code = EXIT_PARTIAL


class PolicyError(GeneratorError):
    exit_code = EXIT_POLICY


class LockUnavailableError(GeneratorError):
    exit_code = EXIT_LOCKED


class PersistenceError(GeneratorError):
    exit_code = EXIT_PERSISTENCE


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate or preserve protected administrative passwords."
    )
    parser.add_argument("--windows-password-file", type=Path, required=True)
    parser.add_argument("--cyclecloud-password-file", type=Path, required=True)
    parser.add_argument("--evidence-file", type=Path, required=True)
    parser.add_argument("--lock-file", type=Path, required=True)
    return parser.parse_args(argv)


def validate_new_password(value: str, policy: PasswordPolicy = POLICY) -> None:
    if len(value) != policy.length:
        raise PolicyError("invalid_password_length")
    if any(char not in policy.allowed_characters for char in value):
        raise PolicyError("invalid_password_character")
    for name, alphabet in zip(
        ("uppercase", "lowercase", "numeric", "special"),
        policy.alphabets,
        strict=True,
    ):
        if sum(char in alphabet for char in value) < policy.minimum_per_class:
            raise PolicyError(f"insufficient_{name}_characters")


def generate_password(
    *,
    policy: PasswordPolicy = POLICY,
    choice: Callable[[str], str] = secrets.choice,
    shuffle: Callable[[list[str]], None] | None = None,
) -> str:
    characters = [
        choice(alphabet)
        for alphabet in policy.alphabets
        for _ in range(policy.minimum_per_class)
    ]
    characters.extend(
        choice(policy.allowed_characters)
        for _ in range(policy.length - len(characters))
    )
    (shuffle or secrets.SystemRandom().shuffle)(characters)
    value = "".join(characters)
    validate_new_password(value, policy)
    return value


def generate_distinct_pair(
    password_factory: Callable[[], str] = generate_password,
) -> tuple[str, str]:
    windows = password_factory()
    validate_new_password(windows)
    for _ in range(32):
        cyclecloud = password_factory()
        validate_new_password(cyclecloud)
        if cyclecloud != windows:
            return windows, cyclecloud
    raise PolicyError("credentials_not_distinct")


def _fail(message: str, exception: type[GeneratorError]) -> NoReturn:
    raise exception(message)


def _validate_parent(path: Path) -> None:
    if not path.is_absolute():
        _fail("path_not_absolute", InputError)
    parent = path.parent
    try:
        parent_stat = parent.stat()
    except OSError as error:
        raise InputError("missing_parent_directory") from error
    if not stat.S_ISDIR(parent_stat.st_mode):
        _fail("invalid_parent_directory", InputError)
    if parent_stat.st_mode & 0o022:
        _fail("unsafe_parent_directory", InputError)


def _validate_distinct_paths(paths: Sequence[Path]) -> None:
    normalized = [os.path.abspath(path) for path in paths]
    if len(set(normalized)) != len(normalized):
        _fail("paths_not_distinct", InputError)
    for path in paths:
        _validate_parent(path)


def _path_exists(path: Path) -> bool:
    return os.path.lexists(path)


def _validate_existing_credential(path: Path) -> None:
    try:
        path_stat = path.lstat()
    except OSError as error:
        raise InputError("credential_stat_failed") from error
    if not stat.S_ISREG(path_stat.st_mode):
        _fail("unsafe_credential_type", InputError)
    if stat.S_IMODE(path_stat.st_mode) != 0o600:
        _fail("unsafe_credential_mode", InputError)


def _read_credential(path: Path) -> str:
    _validate_existing_credential(path)
    try:
        return path.read_text()
    except OSError as error:
        raise PersistenceError("credential_read_failed") from error


def _fsync_directory(directory: Path) -> None:
    directory_fd = os.open(directory, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _atomic_create_secret(path: Path, value: str) -> None:
    temporary_fd = -1
    temporary_name = ""
    try:
        temporary_fd, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            dir=path.parent,
        )
        os.fchmod(temporary_fd, 0o600)
        with os.fdopen(temporary_fd, "w") as stream:
            temporary_fd = -1
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.link(temporary_name, path)
        os.unlink(temporary_name)
        temporary_name = ""
        _fsync_directory(path.parent)
    except FileExistsError as error:
        raise PersistenceError("credential_target_appeared") from error
    except OSError as error:
        raise PersistenceError("credential_write_failed") from error
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        if temporary_name:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


def _atomic_write_json(path: Path, value: object) -> None:
    temporary_fd = -1
    temporary_name = ""
    try:
        temporary_fd, temporary_name = tempfile.mkstemp(
            prefix=f".{path.name}.",
            dir=path.parent,
        )
        os.fchmod(temporary_fd, 0o600)
        with os.fdopen(temporary_fd, "w") as stream:
            temporary_fd = -1
            json.dump(value, stream, indent=2, sort_keys=True)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary_name, path)
        temporary_name = ""
        _fsync_directory(path.parent)
    except OSError as error:
        raise PersistenceError("evidence_write_failed") from error
    finally:
        if temporary_fd >= 0:
            os.close(temporary_fd)
        if temporary_name:
            try:
                os.unlink(temporary_name)
            except FileNotFoundError:
                pass


@contextmanager
def _credential_lock(path: Path):
    flags = os.O_RDWR | os.O_CREAT
    if hasattr(os, "O_NOFOLLOW"):
        flags |= os.O_NOFOLLOW
    try:
        lock_fd = os.open(path, flags, 0o600)
    except OSError as error:
        raise InputError("unsafe_lock_file") from error
    try:
        lock_stat = os.fstat(lock_fd)
        if not stat.S_ISREG(lock_stat.st_mode):
            _fail("unsafe_lock_type", InputError)
        if stat.S_IMODE(lock_stat.st_mode) != 0o600:
            _fail("unsafe_lock_mode", InputError)
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise LockUnavailableError("credential_set_locked") from error
        yield
    finally:
        os.close(lock_fd)


def _evidence(status: str) -> dict[str, object]:
    disposition = "generated" if status == "generated" else "preserved"
    return {
        "schemaVersion": 1,
        "status": status,
        "policyProfile": POLICY.id,
        "targets": [
            {
                "target": target.target,
                "account": target.account,
                "secretName": target.secret_name,
                "disposition": disposition,
            }
            for target in TARGETS
        ],
        "newValuePolicyValidated": True if status == "generated" else None,
        "uniquenessValidated": True,
        "protectedModesValidated": True,
        "completedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
    }


def generate_or_preserve(
    *,
    windows_path: Path,
    cyclecloud_path: Path,
    evidence_path: Path,
    lock_path: Path,
    password_factory: Callable[[], str] = generate_password,
    before_second_write: Callable[[], None] | None = None,
) -> str:
    paths = (windows_path, cyclecloud_path, evidence_path, lock_path)
    _validate_distinct_paths(paths)

    with _credential_lock(lock_path):
        windows_exists = _path_exists(windows_path)
        cyclecloud_exists = _path_exists(cyclecloud_path)
        if windows_exists:
            _validate_existing_credential(windows_path)
        if cyclecloud_exists:
            _validate_existing_credential(cyclecloud_path)
        if windows_exists != cyclecloud_exists:
            raise PartialSetError("partial_credential_set")

        if windows_exists:
            windows = _read_credential(windows_path)
            cyclecloud = _read_credential(cyclecloud_path)
            if windows == cyclecloud:
                raise PolicyError("credentials_not_distinct")
            status = "preserved"
        else:
            windows, cyclecloud = generate_distinct_pair(password_factory)
            _atomic_create_secret(windows_path, windows)
            try:
                if before_second_write is not None:
                    before_second_write()
                _atomic_create_secret(cyclecloud_path, cyclecloud)
            except GeneratorError:
                raise
            except BaseException as error:
                raise PersistenceError("credential_set_interrupted") from error
            _validate_existing_credential(windows_path)
            _validate_existing_credential(cyclecloud_path)
            status = "generated"

        _atomic_write_json(evidence_path, _evidence(status))
        return status


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        status = generate_or_preserve(
            windows_path=args.windows_password_file,
            cyclecloud_path=args.cyclecloud_password_file,
            evidence_path=args.evidence_file,
            lock_path=args.lock_file,
        )
    except GeneratorError as error:
        print(f"error: {error}", file=sys.stderr)
        return error.exit_code
    print(status)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
