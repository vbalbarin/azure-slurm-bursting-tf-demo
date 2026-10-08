from __future__ import annotations

from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import shlex
import stat
import subprocess  # nosec B404 - only the explicit contract validator is executed
import tempfile


class ValidationFailure(RuntimeError):
    pass


class SafeWriteFailure(RuntimeError):
    pass


@dataclass(frozen=True)
class WriteResult:
    changed: bool
    source_digest: str
    destination_digest: str


def digest(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def _validator_arguments(command: str, candidate: Path) -> list[str]:
    arguments = shlex.split(command)
    if not arguments:
        raise ValidationFailure("Validator command is empty")
    candidate_text = str(candidate)
    if any("{candidate}" in argument for argument in arguments):
        return [argument.replace("{candidate}", candidate_text) for argument in arguments]
    return [*arguments, candidate_text]


def write_validated(
    *,
    source: Path,
    destination: Path,
    candidate: str,
    validator: str,
) -> WriteResult:
    source_bytes = source.read_bytes()
    candidate_bytes = candidate.encode("utf-8")
    source_digest = digest(source_bytes)

    existing = destination.read_bytes() if destination.exists() else None
    destination_digest = digest(candidate_bytes)
    if existing == candidate_bytes:
        return WriteResult(
            changed=False,
            source_digest=source_digest,
            destination_digest=destination_digest,
        )

    descriptor = -1
    temporary: Path | None = None
    try:
        descriptor, temporary_name = tempfile.mkstemp(
            prefix=f".{destination.name}.",
            suffix=".tmp",
            dir=destination.parent,
        )
        temporary = Path(temporary_name)
        mode = stat.S_IMODE(destination.stat().st_mode if destination.exists() else source.stat().st_mode)
        with os.fdopen(descriptor, "wb", closefd=True) as handle:
            descriptor = -1
            handle.write(candidate_bytes)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)

        completed = subprocess.run(  # nosec B603 - explicit contract-approved validator only
            _validator_arguments(validator, temporary),
            check=False,
            capture_output=True,
            text=True,
        )
        if completed.returncode != 0:
            diagnostic = completed.stderr.strip() or "validator returned nonzero"
            raise ValidationFailure(diagnostic)

        os.replace(temporary, destination)
        temporary = None
        return WriteResult(
            changed=True,
            source_digest=source_digest,
            destination_digest=destination_digest,
        )
    except ValidationFailure:
        raise
    except OSError as exc:
        raise SafeWriteFailure(f"Safe destination update failed: {exc}") from exc
    finally:
        if descriptor >= 0:
            os.close(descriptor)
        if temporary is not None:
            temporary.unlink(missing_ok=True)
