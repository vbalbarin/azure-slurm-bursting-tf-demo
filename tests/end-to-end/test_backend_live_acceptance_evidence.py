from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any, cast

import pytest
from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).parents[2]
SCHEMA_PATH = (
    ROOT
    / "specs/003-terraform-backend-bootstrap/contracts"
    / "backend-live-acceptance.schema.json"
)


def _validator() -> Draft202012Validator:
    schema = json.loads(SCHEMA_PATH.read_text())
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def live_evidence() -> dict[str, object]:
    access = {"initialized": True, "read_succeeded": True, "lock_succeeded": True}
    plan = {
        "plan_digest": "d" * 64,
        "approval_reference": "CHG-123",
        "stale_plan_rejected": True,
        "applied_digest_matches": True,
    }
    stage = {"recorded": True, "reference": "evidence/stage.json"}
    return {
        "schema_version": "1.0",
        "source_commit": "a" * 40,
        "run_id": "20261014T130000Z",
        "started_at": "2026-10-14T13:00:00Z",
        "completed_at": "2026-10-14T13:25:00Z",
        "bootstrap_elapsed_seconds": 600,
        "role_propagation_delay_seconds": 90,
        "replacement_operator": {
            "tenant_id": "11111111-1111-4111-8111-111111111111",
            "principal_id": "22222222-2222-4222-8222-222222222222",
            "principal_type": "User",
            "authenticated_at": "2026-10-14T13:10:00Z",
            "completed_at": "2026-10-14T13:20:00Z",
            "elapsed_seconds": 600,
        },
        "namespace_access": {
            "bootstrap": access,
            "main": access,
            "capacity_probe": access,
        },
        "reverse_migration": {
            "local_mode": "0600",
            "lineage_matches": True,
            "resource_count_matches": True,
            "stable_state_matches": True,
        },
        "unlock": plan,
        "destroy": {**plan, "approval_reference": "CHG-124"},
        "backend_absence": {"account_absent": True, "container_absent": True},
        "secret_hygiene": {
            "git_scan_passed": True,
            "evidence_scan_passed": True,
            "prohibited_artifact_count": 0,
        },
        "stages": {
            "bootstrap": stage,
            "preliminary_readiness": stage,
            "migration_final_readiness": stage,
            "dependent_initialization_deployment": stage,
            "recovery": stage,
            "unlock": stage,
            "removal": stage,
            "undocumented_command_count": 0,
            "workflow_substitution_count": 0,
        },
        "status": "passed",
    }


def test_representative_live_acceptance_evidence() -> None:
    _validator().validate(live_evidence())


def test_rejects_stopped_run_and_secret_shaped_fields() -> None:
    evidence = live_evidence()
    evidence["run_id"] = "20261013T164853Z"
    assert list(_validator().iter_errors(evidence))

    evidence = live_evidence()
    evidence["account_key"] = "prohibited"
    assert list(_validator().iter_errors(evidence))


@pytest.mark.parametrize(
    ("section", "field"),
    [
        ("namespace_access", "bootstrap"),
        ("namespace_access", "main"),
        ("namespace_access", "capacity_probe"),
    ],
)
def test_passed_evidence_requires_successful_namespace_access(
    section: str, field: str
) -> None:
    evidence = live_evidence()
    cast(dict[str, Any], evidence[section])[field]["lock_succeeded"] = False
    assert list(_validator().iter_errors(evidence))


def test_passed_evidence_requires_all_acceptance_invariants() -> None:
    mutations = (
        ("reverse_migration", "stable_state_matches"),
        ("unlock", "stale_plan_rejected"),
        ("destroy", "applied_digest_matches"),
        ("backend_absence", "account_absent"),
        ("secret_hygiene", "evidence_scan_passed"),
    )
    for section, field in mutations:
        evidence = live_evidence()
        cast(dict[str, Any], evidence[section])[field] = False
        assert list(_validator().iter_errors(evidence))

    evidence = live_evidence()
    cast(dict[str, Any], evidence["stages"])["recovery"]["recorded"] = False
    assert list(_validator().iter_errors(evidence))


def test_external_live_acceptance_evidence_when_requested() -> None:
    evidence_path = os.environ.get("BACKEND_LIVE_ACCEPTANCE_EVIDENCE")
    if not evidence_path:
        pytest.skip("BACKEND_LIVE_ACCEPTANCE_EVIDENCE was not provided")
    _validator().validate(json.loads(Path(evidence_path).read_text()))
