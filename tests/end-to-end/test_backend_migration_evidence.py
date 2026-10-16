from __future__ import annotations

import json
import os
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).parents[2]
SCHEMA_PATH = (
    ROOT
    / "specs/003-terraform-backend-bootstrap/contracts"
    / "backend-migration-acceptance.schema.json"
)


def _validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def migration_evidence() -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "source_commit": "a" * 40,
        "observed_at": "2026-10-14T13:00:00Z",
        "coordinates_digest": "b" * 64,
        "local_state": {
            "path_class": "protected_state_volume",
            "mode": "0600",
            "lineage": "11111111-1111-4111-8111-111111111111",
            "resource_count": 4,
            "digest": "c" * 64,
            "retained_until_verified": True,
            "named_files_absent_after_deletion": True,
        },
        "remote_state": {
            "pull_succeeded": True,
            "lineage": "11111111-1111-4111-8111-111111111111",
            "resource_count": 4,
            "key": "dev/bootstrap.tfstate",
        },
        "lineage_matches": True,
        "resource_count_matches": True,
        "no_change_plan": {"exit_code": 0, "result": True},
        "saved_plan_continuity": {"exit_code": 0, "result": True},
        "lock_conflict": {
            "first_operation_acquired": True,
            "first_operation_released": True,
            "second_operation_rejected": True,
        },
        "namespaces": {
            "bootstrap": "dev/bootstrap.tfstate",
            "main": "dev/main.tfstate",
            "capacity_probe": "dev/capacity-probe.tfstate",
            "pairwise_distinct": True,
            "isolation_verified": True,
        },
        "verification_status": "passed",
    }


def test_representative_migration_evidence() -> None:
    _validator().validate(migration_evidence())


def test_passed_evidence_rejects_unverified_or_retained_local_state() -> None:
    evidence = migration_evidence()
    evidence["local_state"]["retained_until_verified"] = False
    assert list(_validator().iter_errors(evidence))


def test_passed_evidence_requires_saved_plan_continuity() -> None:
    evidence = migration_evidence()
    evidence["saved_plan_continuity"] = {"exit_code": 1, "result": False}
    assert list(_validator().iter_errors(evidence))


def test_external_migration_evidence_when_requested() -> None:
    evidence_path = os.environ.get("BACKEND_MIGRATION_EVIDENCE")
    if not evidence_path:
        pytest.skip("BACKEND_MIGRATION_EVIDENCE was not provided")
    _validator().validate(json.loads(Path(evidence_path).read_text()))
