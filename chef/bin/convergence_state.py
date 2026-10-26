#!/usr/bin/env python3
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import tempfile


HEX40 = re.compile(r"^[0-9a-f]{40}$")
HEX64 = re.compile(r"^[0-9a-f]{64}$")
STATES = {
    "staging",
    "environment_ready",
    "waiting_dependencies",
    "converging",
    "failed_retryable",
    "replacement_required",
    "converged",
    "verifying_idempotency",
    "idempotency_verified",
    "update_authorized",
    "failed",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--state-dir", type=Path, default=Path("/var/lib/slurm-demo"))
    subparsers = parser.add_subparsers(dest="command", required=True)
    transition = subparsers.add_parser("transition")
    transition.add_argument("--role", choices=("cyclecloud", "scheduler"), required=True)
    transition.add_argument("--source-revision", required=True)
    transition.add_argument("--manifest-digest", required=True)
    transition.add_argument("--specification-digest", required=True)
    transition.add_argument("--state", choices=sorted(STATES), required=True)
    transition.add_argument("--attempt", type=int, choices=(0, 1, 2), required=True)
    transition.add_argument("--detail-code", default="ok")
    evidence = subparsers.add_parser("record-evidence")
    evidence.add_argument("--role", choices=("cyclecloud", "scheduler"), required=True)
    evidence.add_argument("--source-revision", required=True)
    evidence.add_argument("--manifest-digest", required=True)
    evidence.add_argument("--specification-digest", required=True)
    evidence.add_argument("--policy-revision", required=True)
    evidence.add_argument("--policy-lock-sha256", required=True)
    evidence.add_argument("--attempt", type=int, choices=(1, 2), required=True)
    evidence.add_argument("--result", choices=("succeeded", "failed", "interrupted"), required=True)
    evidence.add_argument("--state", required=True)
    evidence.add_argument("--updated-resources", type=int)
    evidence.add_argument("--started-at", required=True)
    evidence.add_argument("--finished-at", required=True)
    evidence.add_argument("--cleanup-verified", action="store_true")
    evidence.add_argument("--failure-stage")
    evidence.add_argument("--dependency-receipt", action="append", default=[])
    evidence.add_argument("--hpc-user-uid", type=int)
    evidence.add_argument("--hpc-user-gid", type=int)
    evidence.add_argument("--hpc-user-key-fingerprint")
    return parser.parse_args()


def atomic_write(path: Path, document: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as output:
            json.dump(document, output, indent=2, sort_keys=True)
            output.write("\n")
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, 0o600)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def transition(arguments: argparse.Namespace) -> None:
    if not HEX40.fullmatch(arguments.source_revision):
        raise SystemExit("invalid source revision")
    for value in (arguments.manifest_digest, arguments.specification_digest):
        if not HEX64.fullmatch(value):
            raise SystemExit("invalid digest")
    if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", arguments.detail_code):
        raise SystemExit("invalid detail code")

    role_dir = arguments.state_dir / arguments.role
    role_dir.mkdir(parents=True, exist_ok=True, mode=0o700)
    lock_path = role_dir / "convergence.lock"
    with lock_path.open("a+", encoding="utf-8") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise SystemExit("role convergence is already active") from error

        state_path = role_dir / "state.json"
        previous = json.loads(state_path.read_text()) if state_path.exists() else None
        if previous and previous["state"] == "replacement_required":
            raise SystemExit("replacement is required")
        if arguments.attempt == 2 and arguments.state == "converging":
            if not previous or previous["state"] != "failed_retryable":
                raise SystemExit("attempt 2 requires failed_retryable")
            for key, value in (
                ("sourceRevision", arguments.source_revision),
                ("manifestDigest", arguments.manifest_digest),
                ("specificationDigest", arguments.specification_digest),
            ):
                if previous[key] != value:
                    raise SystemExit("retry inputs changed")
        if previous and arguments.attempt <= previous["attempt"]:
            changed = any(
                previous[key] != value
                for key, value in (
                    ("sourceRevision", arguments.source_revision),
                    ("manifestDigest", arguments.manifest_digest),
                    ("specificationDigest", arguments.specification_digest),
                )
            )
            if changed and arguments.state != "update_authorized":
                raise SystemExit("state inputs changed without update authorization")

        atomic_write(
            state_path,
            {
                "schemaVersion": 1,
                "role": arguments.role,
                "state": arguments.state,
                "sourceRevision": arguments.source_revision,
                "manifestDigest": arguments.manifest_digest,
                "specificationDigest": arguments.specification_digest,
                "attempt": arguments.attempt,
                "updatedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
                "detailCode": arguments.detail_code,
            },
        )


def record_evidence(arguments: argparse.Namespace) -> None:
    if not HEX40.fullmatch(arguments.source_revision):
        raise SystemExit("invalid source revision")
    for value in (
        arguments.manifest_digest,
        arguments.specification_digest,
        arguments.policy_revision,
        arguments.policy_lock_sha256,
    ):
        if not HEX64.fullmatch(value):
            raise SystemExit("invalid digest")
    if arguments.updated_resources is not None and arguments.updated_resources < 0:
        raise SystemExit("updated resources cannot be negative")
    if arguments.failure_stage and not re.fullmatch(
        r"[a-z0-9][a-z0-9_-]{0,63}", arguments.failure_stage
    ):
        raise SystemExit("invalid failure stage")
    try:
        started_at = datetime.fromisoformat(arguments.started_at.replace("Z", "+00:00"))
        finished_at = datetime.fromisoformat(arguments.finished_at.replace("Z", "+00:00"))
    except ValueError as error:
        raise SystemExit("invalid evidence timestamp") from error
    if started_at.tzinfo is None or finished_at.tzinfo is None:
        raise SystemExit("evidence timestamps require timezones")
    if finished_at < started_at:
        raise SystemExit("finished timestamp precedes started timestamp")
    dependency_receipts = []
    for receipt in arguments.dependency_receipt:
        try:
            name, digest = receipt.split("=", 1)
        except ValueError as error:
            raise SystemExit("dependency receipt must use name=digest") from error
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", name):
            raise SystemExit("invalid dependency receipt name")
        if not HEX64.fullmatch(digest):
            raise SystemExit("invalid dependency receipt digest")
        dependency_receipts.append(
            {"name": name, "digest": digest, "result": "passed"}
        )
    hpc_values = (
        arguments.hpc_user_uid,
        arguments.hpc_user_gid,
        arguments.hpc_user_key_fingerprint,
    )
    if any(value is not None for value in hpc_values) and not all(
        value is not None for value in hpc_values
    ):
        raise SystemExit("all HPC user evidence fields are required together")
    if arguments.hpc_user_uid is not None:
        if arguments.hpc_user_uid != 11200 or arguments.hpc_user_gid != 11200:
            raise SystemExit("invalid HPC user identity")
        if len(arguments.hpc_user_key_fingerprint) < 16:
            raise SystemExit("invalid HPC user key fingerprint")
    document: dict[str, object] = {
        "schemaVersion": 1,
        "role": arguments.role,
        "sourceRevision": arguments.source_revision,
        "manifestDigest": arguments.manifest_digest,
        "specificationDigest": arguments.specification_digest,
        "policyRevision": arguments.policy_revision,
        "policyLockSha256": arguments.policy_lock_sha256,
        "chefVersion": "18.11.11",
        "slurmProjectVersion": "4.0.11",
        "attempt": arguments.attempt,
        "startedAt": arguments.started_at,
        "finishedAt": arguments.finished_at,
        "result": arguments.result,
        "state": arguments.state,
        "updatedResources": arguments.updated_resources,
        "dependencyReceipts": dependency_receipts,
        "cleanupVerified": arguments.cleanup_verified,
        "failureStage": arguments.failure_stage,
    }
    if arguments.hpc_user_uid is not None:
        document["hpcUser"] = {
            "uid": arguments.hpc_user_uid,
            "gid": arguments.hpc_user_gid,
            "publicKeyFingerprint": arguments.hpc_user_key_fingerprint,
        }
    evidence_path = (
        arguments.state_dir
        / arguments.role
        / "evidence"
        / f"attempt-{arguments.attempt}-{arguments.state}.json"
    )
    if evidence_path.exists():
        existing = json.loads(evidence_path.read_text())
        if existing != document:
            raise SystemExit("evidence record already exists with different content")
        return
    atomic_write(evidence_path, document)


def main() -> None:
    arguments = parse_args()
    if arguments.command == "transition":
        transition(arguments)
    elif arguments.command == "record-evidence":
        record_evidence(arguments)


if __name__ == "__main__":
    main()
