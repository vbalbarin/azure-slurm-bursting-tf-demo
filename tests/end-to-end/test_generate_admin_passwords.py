from __future__ import annotations

import fcntl
import importlib.util
import json
import os
from pathlib import Path
import re
import subprocess
import sys

import pytest


ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / "tests/end-to-end/generate_admin_passwords.py"
SPEC = importlib.util.spec_from_file_location("generate_admin_passwords", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
passwords = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = passwords
SPEC.loader.exec_module(passwords)


@pytest.fixture
def protected_dir(tmp_path: Path) -> Path:
    path = tmp_path / "protected"
    path.mkdir(mode=0o700)
    return path


@pytest.fixture
def credential_paths(protected_dir: Path) -> dict[str, Path]:
    return {
        "windows": protected_dir / "windows-admin-password",
        "cyclecloud": protected_dir / "cyclecloud-admin-password",
        "evidence": protected_dir / "admin-password-evidence.json",
        "lock": protected_dir / "admin-passwords.lock",
    }


def _run(paths: dict[str, Path]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            sys.executable,
            str(SCRIPT),
            "--windows-password-file",
            str(paths["windows"]),
            "--cyclecloud-password-file",
            str(paths["cyclecloud"]),
            "--evidence-file",
            str(paths["evidence"]),
            "--lock-file",
            str(paths["lock"]),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def _assert_policy(value: str) -> None:
    assert len(value) == 16
    assert set(value) <= set(passwords.POLICY.allowed_characters)
    assert sum(char in passwords.POLICY.uppercase_alphabet for char in value) >= 2
    assert sum(char in passwords.POLICY.lowercase_alphabet for char in value) >= 2
    assert sum(char in passwords.POLICY.numeric_alphabet for char in value) >= 2
    assert sum(char in passwords.POLICY.special_alphabet for char in value) >= 2


def test_policy_and_target_metadata_are_exact() -> None:
    assert passwords.POLICY.id == "interactive-admin-v1"
    assert passwords.POLICY.length == 16
    assert passwords.POLICY.uppercase_alphabet == "ABCDEFGHJKLMNPQRSTUVWXYZ"
    assert passwords.POLICY.lowercase_alphabet == "abcdefghijkmnopqrstuvwxyz"
    assert passwords.POLICY.numeric_alphabet == "23456789"
    assert passwords.POLICY.special_alphabet == "!@#$%^*()-_+="
    assert passwords.POLICY.minimum_per_class == 2
    assert [
        (target.target, target.account, target.secret_name)
        for target in passwords.TARGETS
    ] == [
        ("windows", "windowsadmin", "windows-admin-password"),
        ("cyclecloud", "hpcadmin", "cyclecloud-admin-password"),
    ]


def test_cli_has_no_literal_password_argument() -> None:
    help_result = subprocess.run(
        [sys.executable, str(SCRIPT), "--help"],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert help_result.returncode == 0
    assert "--windows-password-file" in help_result.stdout
    assert "--cyclecloud-password-file" in help_result.stdout
    assert not re.search(r"(?<!-)--password(?:\\s|$)", help_result.stdout)


def test_generated_password_always_satisfies_policy() -> None:
    for _ in range(100):
        _assert_policy(passwords.generate_password())


def test_distinct_pair_retries_a_first_collision() -> None:
    values = iter(
        [
            "AAaa22!!AAaa22!!",
            "AAaa22!!AAaa22!!",
            "BBbb33@@BBbb33@@",
        ]
    )

    assert passwords.generate_distinct_pair(lambda: next(values)) == (
        "AAaa22!!AAaa22!!",
        "BBbb33@@BBbb33@@",
    )


def test_distinct_pair_rejects_bounded_repeated_collisions() -> None:
    with pytest.raises(passwords.PolicyError, match="credentials_not_distinct"):
        passwords.generate_distinct_pair(lambda: "AAaa22!!AAaa22!!")


@pytest.mark.parametrize(
    "value",
    [
        "Aa2!Aa2!Aa2!Aa2",
        "AA22!!AA22!!AA22",
        "aa22!!aa22!!aa22",
        "AAaa!!AAaa!!AAaa",
        "AAaa22AAaa22AAaa",
        "AAaa22!!AAaa22!/",
    ],
)
def test_invalid_values_fail_policy_validation(value: str) -> None:
    with pytest.raises(passwords.PolicyError):
        passwords.validate_new_password(value)


def test_new_set_is_distinct_protected_and_value_free(
    credential_paths: dict[str, Path],
) -> None:
    result = _run(credential_paths)

    assert result.returncode == 0, result.stderr
    assert result.stdout == "generated\n"
    windows = credential_paths["windows"].read_text()
    cyclecloud = credential_paths["cyclecloud"].read_text()
    _assert_policy(windows)
    _assert_policy(cyclecloud)
    assert windows != cyclecloud
    assert credential_paths["windows"].stat().st_mode & 0o777 == 0o600
    assert credential_paths["cyclecloud"].stat().st_mode & 0o777 == 0o600
    evidence_text = credential_paths["evidence"].read_text()
    assert windows not in result.stdout + result.stderr + evidence_text
    assert cyclecloud not in result.stdout + result.stderr + evidence_text
    evidence = json.loads(evidence_text)
    assert evidence["status"] == "generated"
    assert evidence["newValuePolicyValidated"] is True
    assert evidence["uniquenessValidated"] is True
    assert evidence["protectedModesValidated"] is True
    assert evidence["targets"] == [
        {
            "target": "windows",
            "account": "windowsadmin",
            "secretName": "windows-admin-password",
            "disposition": "generated",
        },
        {
            "target": "cyclecloud",
            "account": "hpcadmin",
            "secretName": "cyclecloud-admin-password",
            "disposition": "generated",
        },
    ]


def test_complete_set_is_preserved_without_rewrite(
    credential_paths: dict[str, Path],
) -> None:
    assert _run(credential_paths).returncode == 0
    before = {
        name: (
            credential_paths[name].read_bytes(),
            credential_paths[name].stat().st_ino,
            credential_paths[name].stat().st_mtime_ns,
        )
        for name in ("windows", "cyclecloud")
    }

    result = _run(credential_paths)

    assert result.returncode == 0, result.stderr
    assert result.stdout == "preserved\n"
    after = {
        name: (
            credential_paths[name].read_bytes(),
            credential_paths[name].stat().st_ino,
            credential_paths[name].stat().st_mtime_ns,
        )
        for name in ("windows", "cyclecloud")
    }
    assert after == before
    evidence = json.loads(credential_paths["evidence"].read_text())
    assert evidence["status"] == "preserved"
    assert evidence["newValuePolicyValidated"] is None


def test_partial_set_fails_without_creating_missing_file(
    credential_paths: dict[str, Path],
) -> None:
    credential_paths["windows"].write_text("legacy-value")
    credential_paths["windows"].chmod(0o600)

    result = _run(credential_paths)

    assert result.returncode == passwords.EXIT_PARTIAL
    assert "partial_credential_set" in result.stderr
    assert credential_paths["windows"].read_text() == "legacy-value"
    assert not credential_paths["cyclecloud"].exists()
    assert not credential_paths["evidence"].exists()


def test_equal_existing_values_fail_without_rewrite(
    credential_paths: dict[str, Path],
) -> None:
    for name in ("windows", "cyclecloud"):
        credential_paths[name].write_text("same-legacy-value")
        credential_paths[name].chmod(0o600)

    result = _run(credential_paths)

    assert result.returncode == passwords.EXIT_POLICY
    assert "credentials_not_distinct" in result.stderr
    assert not credential_paths["evidence"].exists()


def test_symlink_target_is_rejected(credential_paths: dict[str, Path]) -> None:
    target = credential_paths["windows"].parent / "elsewhere"
    target.write_text("unchanged")
    credential_paths["windows"].symlink_to(target)

    result = _run(credential_paths)

    assert result.returncode == passwords.EXIT_INPUT
    assert target.read_text() == "unchanged"
    assert not credential_paths["cyclecloud"].exists()


def test_unsafe_existing_mode_is_rejected(
    credential_paths: dict[str, Path],
) -> None:
    for name in ("windows", "cyclecloud"):
        credential_paths[name].write_text(f"legacy-{name}")
        credential_paths[name].chmod(0o644)

    result = _run(credential_paths)

    assert result.returncode == passwords.EXIT_INPUT
    assert "unsafe_credential_mode" in result.stderr


def test_unsafe_parent_mode_is_rejected(
    tmp_path: Path,
    credential_paths: dict[str, Path],
) -> None:
    credential_paths["windows"].parent.chmod(0o777)
    try:
        result = _run(credential_paths)
    finally:
        credential_paths["windows"].parent.chmod(0o700)

    assert result.returncode == passwords.EXIT_INPUT
    assert "unsafe_parent_directory" in result.stderr


def test_active_lock_is_rejected(credential_paths: dict[str, Path]) -> None:
    lock_fd = os.open(
        credential_paths["lock"],
        os.O_RDWR | os.O_CREAT,
        0o600,
    )
    try:
        fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = _run(credential_paths)
    finally:
        os.close(lock_fd)

    assert result.returncode == passwords.EXIT_LOCKED
    assert "credential_set_locked" in result.stderr


def test_injected_interruption_leaves_reviewable_partial_state(
    credential_paths: dict[str, Path],
) -> None:
    def interrupt() -> None:
        raise InterruptedError("test interruption")

    with pytest.raises(passwords.PersistenceError):
        passwords.generate_or_preserve(
            windows_path=credential_paths["windows"],
            cyclecloud_path=credential_paths["cyclecloud"],
            evidence_path=credential_paths["evidence"],
            lock_path=credential_paths["lock"],
            before_second_write=interrupt,
        )

    assert credential_paths["windows"].is_file()
    assert not credential_paths["cyclecloud"].exists()
    assert not credential_paths["evidence"].exists()
