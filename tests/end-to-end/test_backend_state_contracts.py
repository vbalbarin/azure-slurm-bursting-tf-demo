from __future__ import annotations

from copy import deepcopy
import hashlib
import json
from pathlib import Path

import pytest
from jsonschema import Draft202012Validator, FormatChecker
from referencing import Registry, Resource


ROOT = Path(__file__).parents[2]
CONTRACTS = ROOT / "specs/003-terraform-backend-bootstrap/contracts"


def _schemas() -> tuple[dict[str, dict[str, object]], Registry]:
    schemas = {
        path.name: json.loads(path.read_text())
        for path in CONTRACTS.glob("*.schema.json")
    }
    registry = Registry()
    for schema in schemas.values():
        Draft202012Validator.check_schema(schema)
        registry = registry.with_resource(
            str(schema["$id"]), Resource.from_contents(schema)
        )
    return schemas, registry


def _validator(name: str) -> Draft202012Validator:
    schemas, registry = _schemas()
    return Draft202012Validator(
        schemas[name], registry=registry, format_checker=FormatChecker()
    )


def test_main_readiness_uses_backend_namespace_not_workload_name() -> None:
    variables = (ROOT / "terraform/variables.tf").read_text()
    readiness = (ROOT / "terraform/backend-readiness.tf").read_text()
    demo_inputs = (ROOT / "terraform/environments/demo.tfvars.example").read_text()
    normalized_demo_inputs = " ".join(demo_inputs.split())

    assert 'variable "backend_environment_name"' in variables
    assert '${var.backend_environment_name}/main.tfstate' in readiness
    assert '${var.backend_environment_name}/capacity-probe.tfstate' in readiness
    assert '${var.backend_environment_name}/bootstrap.tfstate' in readiness
    assert '${var.environment_name}/main.tfstate' not in readiness
    assert 'environment_name = "slurmdemo"' in normalized_demo_inputs
    assert 'backend_environment_name = "demo"' in normalized_demo_inputs


def test_capacity_probe_readiness_uses_backend_namespace_not_workload_name() -> None:
    variables = (ROOT / "terraform/capacity-probe/variables.tf").read_text()
    readiness = (ROOT / "terraform/capacity-probe/backend-readiness.tf").read_text()
    probe_inputs = (
        ROOT / "terraform/capacity-probe/probe.tfvars.example"
    ).read_text()
    normalized_probe_inputs = " ".join(probe_inputs.split())

    assert 'variable "backend_environment_name"' in variables
    assert '${var.backend_environment_name}/main.tfstate' in readiness
    assert '${var.backend_environment_name}/capacity-probe.tfstate' in readiness
    assert '${var.backend_environment_name}/bootstrap.tfstate' in readiness
    assert '${var.environment_name}/main.tfstate' not in readiness
    assert 'environment_name = "slurmdemo"' in normalized_probe_inputs
    assert 'backend_environment_name = "demo"' in normalized_probe_inputs


def coordinates() -> dict[str, object]:
    return {
        "schema_version": "1.0",
        "ownership_mode": "managed",
        "subscription_id": "11111111-1111-4111-8111-111111111111",
        "tenant_id": "22222222-2222-4222-8222-222222222222",
        "resource_group_name": "rg-slurm-dev-eus-01",
        "storage_account_name": "stslurmdveus01abcd",
        "container_name": "tfstate",
        "network_mode": "restricted_public",
        "state_keys": {
            "bootstrap": "dev/bootstrap.tfstate",
            "main": "dev/main.tfstate",
            "capacity_probe": "dev/capacity-probe.tfstate",
        },
        "resource_ids": {
            "resource_group": "/subscriptions/1/resourceGroups/rg",
            "storage_account": "/subscriptions/1/resourceGroups/rg/providers/Microsoft.Storage/storageAccounts/st",
            "container": "/blobServices/default/containers/tfstate",
            "private_endpoint": None,
        },
    }


def execution_context() -> dict[str, object]:
    return {
        "network_mode": "restricted_public",
        "runner_context_digest": "d" * 64,
        "observed_public_source_ipv4": "203.0.113.10",
        "private_network_context_digest": None,
        "resolved_blob_ipv4_addresses": ["20.1.2.3"],
        "observed_at": "2026-10-14T13:00:00Z",
    }


def assertions(*, final: bool = True) -> dict[str, object]:
    commands = {
        "account_context": "az_account_show",
        "backend_exists": "az_storage_account_show",
        "container_exists": "az_storage_container_show",
        "dns": "getent_blob_endpoint",
        "network": "curl_blob_endpoint",
        "authorization": "az_storage_blob_list",
        "state_key_separation": "terraform_coordinate_check",
        "migration": "terraform_state_pull",
        "locking": "terraform_lock_conflict",
    }
    checks: dict[str, object] = {
        key: {
            "command_id": command,
            "observed_at": "2026-10-14T13:00:00Z",
            "exit_code": 0,
            "status": "passed",
            "observed_value": "passed",
        }
        for key, command in commands.items()
    }
    if not final:
        for key in ("migration", "locking"):
            checks[key] = {
                **checks[key],
                "exit_code": None,
                "status": "not_run",
                "observed_value": "",
            }
    return {
        "schema_version": "1.0",
        "source_commit": "a" * 40,
        "coordinates_digest": "b" * 64,
        "assessment_started_at": "2026-10-14T12:59:00Z",
        "assessment_completed_at": "2026-10-14T13:01:00Z",
        "execution_context": execution_context(),
        "checks": checks,
    }


def readiness() -> dict[str, object]:
    check_results = {
        key: {"status": "passed"}
        for key in (
            "account_context",
            "backend_exists",
            "container_exists",
            "dns",
            "network",
            "authorization",
            "state_key_separation",
            "migration",
            "locking",
        )
    }
    return {
        "schema_version": "1.0",
        "source_commit": "a" * 40,
        "assessed_at": "2026-10-14T13:01:00Z",
        "status": "ready",
        "failure_class": "none",
        "identity": {
            "tenant_id": "22222222-2222-4222-8222-222222222222",
            "principal_id": "33333333-3333-4333-8333-333333333333",
            "principal_type": "User",
        },
        "execution_context": execution_context(),
        "coordinates": coordinates(),
        "checks": check_results,
    }


def managed_removal() -> dict[str, object]:
    approved_plan = {
        "plan_sha256": "c" * 64,
        "approval_reference": "CHG-123",
        "stale_plan_rejected": True,
        "applied_plan_digest_matches": True,
    }
    return {
        "schema_version": "1.0",
        "source_commit": "a" * 40,
        "removal_run_id": "20261015T010203Z",
        "completed_at": "2026-10-15T01:05:00Z",
        "removal_path": "abandoned_pre_migration_cleanup",
        "state_migration_status": "never_migrated",
        "reverse_migration_verified": False,
        "dependent_namespaces": {
            "main": {
                "status": "absent",
                "managed_resource_count": 0,
            },
            "capacity_probe": {
                "status": "absent",
                "managed_resource_count": 0,
            },
        },
        "unlock": approved_plan,
        "destroy": {
            **approved_plan,
            "approval_reference": "CHG-124",
        },
        "backend_absence": {
            "account_absent": True,
            "container_absent": True,
        },
        "status": "passed",
    }


@pytest.mark.parametrize(
    ("schema", "document"),
    [
        ("backend-coordinates.schema.json", coordinates()),
        ("backend-readiness-assertions.schema.json", assertions()),
        ("backend-readiness-assertions.schema.json", assertions(final=False)),
        ("backend-readiness.schema.json", readiness()),
        ("backend-managed-removal.schema.json", managed_removal()),
    ],
)
def test_representative_contract_documents(
    schema: str, document: dict[str, object]
) -> None:
    _validator(schema).validate(document)


def test_rejects_wrong_command_id_and_contradictory_not_run() -> None:
    validator = _validator("backend-readiness-assertions.schema.json")
    wrong_command = assertions()
    wrong_command["checks"]["dns"]["command_id"] = "unknown"
    assert list(validator.iter_errors(wrong_command))

    contradictory = assertions(final=False)
    contradictory["checks"]["migration"]["exit_code"] = 0
    assert list(validator.iter_errors(contradictory))


def test_rejects_context_mode_mismatch() -> None:
    validator = _validator("backend-readiness-assertions.schema.json")
    document = assertions()
    document["execution_context"]["observed_public_source_ipv4"] = None
    assert list(validator.iter_errors(document))


def test_rejects_failed_readiness_with_none_failure_class() -> None:
    validator = _validator("backend-readiness.schema.json")
    document = readiness()
    document["status"] = "failed"
    assert list(validator.iter_errors(document))


def test_abandoned_cleanup_cannot_claim_acceptance_or_reverse_migration() -> None:
    validator = _validator("backend-managed-removal.schema.json")

    acceptance = managed_removal()
    acceptance["removal_path"] = "acceptance"
    assert list(validator.iter_errors(acceptance))

    reverse_migrated = managed_removal()
    reverse_migrated["state_migration_status"] = "reverse_migrated"
    reverse_migrated["reverse_migration_verified"] = True
    assert list(validator.iter_errors(reverse_migrated))


def test_approval_digest_matches_exact_plan(tmp_path: Path) -> None:
    plan = tmp_path / "bootstrap.tfplan"
    plan.write_bytes(b"reviewed plan")
    approval = {
        "schema_version": "1.0",
        "action": "create",
        "source_commit": "a" * 40,
        "input_digest": "b" * 64,
        "plan_digest": hashlib.sha256(plan.read_bytes()).hexdigest(),
        "plan_created_at": "2026-10-14T13:00:00Z",
        "approved_at": "2026-10-14T13:05:00Z",
        "approval_reference": "CHG-123",
    }
    _validator("backend-plan-approval.schema.json").validate(approval)
    assert approval["plan_digest"] == hashlib.sha256(plan.read_bytes()).hexdigest()

    changed = deepcopy(approval)
    changed["plan_digest"] = "0" * 64
    assert changed["plan_digest"] != hashlib.sha256(plan.read_bytes()).hexdigest()


def test_contract_examples_contain_no_secret_shaped_fields() -> None:
    payload = json.dumps(
        {
            "coordinates": coordinates(),
            "assertions": assertions(),
            "readiness": readiness(),
            "managed_removal": managed_removal(),
        }
    ).lower()
    for forbidden in ("access_token", "sas_token", "account_key", "password"):
        assert forbidden not in payload


@pytest.mark.parametrize(
    "name",
    [
        "backend-migration-acceptance.schema.json",
        "backend-live-acceptance.schema.json",
    ],
)
def test_acceptance_contracts_are_valid_and_closed(name: str) -> None:
    schemas, _ = _schemas()
    assert schemas[name]["additionalProperties"] is False


def test_local_backend_uses_runtime_protected_path_contract() -> None:
    backend = (ROOT / "terraform/bootstrap/backend.local.tf.example").read_text()
    devcontainer = json.loads((ROOT / ".devcontainer/devcontainer.json").read_text())
    post_create = (ROOT / ".devcontainer/post-create.sh").read_text()
    readme = (ROOT / "README.md").read_text()
    gitignore = (ROOT / ".gitignore").read_text()

    assert 'backend "local" {}' in backend
    assert (
        devcontainer["containerEnv"]["BOOTSTRAP_STATE_ROOT"]
        == "/state/terraform-backend"
    )
    assert (
        "source=azure-slurm-bursting-tf-demo-state,target=/state,type=volume"
        in devcontainer["mounts"]
    )
    assert 'chmod 0700 "$STATE_ROOT"' in post_create
    assert 'install -d -m 0700 "$BOOTSTRAP_STATE_ROOT"' in post_create
    assert "**/backend.local.tf" in gitignore
    assert "${BOOTSTRAP_STATE_ROOT}/${BACKEND_ENVIRONMENT}" in readme
    assert "terraform.tfstate.backup" in readme
    assert "timestamped Terraform backup variants" in readme
    assert "mode-`0600` local copy" in readme
    assert "mode `0700`" in readme
    assert "SHA-256 digests" in readme
    assert "confirm each is absent" in readme
    assert "underlying physical" in readme


def test_detailed_runbook_uses_supported_removal_commands() -> None:
    runbook = (ROOT / "docs/quickstart-evidence-runbook.md").read_text()
    migration = runbook.split("## A6. Migrate bootstrap state", 1)[1].split(
        "## A7. Produce final readiness", 1
    )[0]
    remote_no_change = migration.split(
        'export REMOTE_NO_CHANGE_LOG="$BOOTSTRAP_STATE_DIR/remote-no-change.log"',
        1,
    )[1].split("Acquire an infinite Azure Blob lease", 1)[0]

    assert "--resource-type Microsoft.Storage/storageAccounts" in runbook
    assert '--scope "$STORAGE_ACCOUNT_RESOURCE_ID"' not in runbook
    assert 'DESTROY_PIPE_STATUSES=("${PIPESTATUS[@]}")' in runbook
    assert (
        'test "$DESTROY_APPROVAL_REFERENCE" != "$UNLOCK_APPROVAL_REFERENCE"'
        not in runbook
    )
    assert "from referencing import Registry, Resource" in runbook
    assert "run A1 through A8" in runbook
    assert "execute A9 after B10 and before B11" in runbook
    assert "return to a10 only after" in runbook.lower()
    assert "FINAL_RESOURCE_CHANGE_COUNT" in runbook
    assert "FINAL_OUTPUT_CHANGE_COUNT" in runbook
    assert "BOOTSTRAP_RECOVERY_PLAN_STATUS" in runbook
    assert "RECOVERY_ELAPSED_SECONDS" in runbook
    assert 'test "$RECOVERY_ELAPSED_SECONDS" -le 900' in runbook
    assert 'export APPROVAL_WAIT_SECONDS="$(' in runbook
    assert '"$BOOTSTRAP_CREATE_APPROVAL"' in runbook
    assert '"$PRELIMINARY_APPROVAL"' in runbook
    assert '"$FINAL_APPROVAL"' in runbook
    assert "ROLE_PROPAGATION_DELAY_SECONDS -" in runbook
    assert "APPROVAL_WAIT_SECONDS" in runbook
    assert 'test "$BOOTSTRAP_ELAPSED_SECONDS" -le 1200' in runbook
    assert 'test "$REVERSE_STABLE_STATE_MATCHES" = "true"' in runbook
    assert "MIGRATION_SAVED_PLAN_CONTINUITY" in runbook
    assert "MIGRATION_STALE_REJECTED" not in runbook
    assert "-detailed-exitcode" in remote_no_change
    assert "-refresh-only" not in remote_no_change
    assert "normal plan refreshes remote" in migration
    assert "--query leaseId" not in migration
    assert '[[ "$LOCK_LEASE_ID" =~ ^[0-9a-fA-F]{8}-' in migration
    assert "az storage blob lease break" in migration
    assert "unset LOCK_LEASE_ID" in migration
    assert "jq -S -c '{lineage, outputs, resources}'" in runbook
    assert "backend-live-acceptance.json" in runbook
    assert "abandoned_pre_migration_cleanup" in runbook
    assert "## B11. Remove the main deployment" in runbook
    assert "MAIN_DESTROY_APPROVAL" in runbook
    assert "MAIN_DESTROY_STALE_REJECTED" in runbook
    assert "BURST_PIPE_STATUSES" in runbook
    assert "FINAL_PLAN_PIPE_STATUSES" in runbook
    assert not any(line.strip() == "set -e" for line in runbook.splitlines())
    assert 'NETWORK_HEADER_FILE="$BOOTSTRAP_STATE_DIR/blob-network-headers.txt"' in runbook
    assert "409 Public access is not permitted on this storage account" in runbook
    assert "tr -d '\\r' <\"$NETWORK_HEADER_FILE\"" in runbook
    assert 'NETWORK_OBSERVED_VALUE="http_status=409_public_access_not_permitted"' in runbook
    assert "--arg network_observed_value" in runbook
    assert "COORDINATES_DOCUMENT_DIGEST" in runbook
    assert (
        'jq -jc . "$BACKEND_EVIDENCE_DIR/backend-coordinates.json" |\n'
        "  sha256sum |"
        in runbook
    )
    assert "TERRAFORM_COORDINATES_DIGEST" in runbook
    assert (
        'test "$COORDINATES_DIGEST" = "$TERRAFORM_COORDINATES_DIGEST"'
        in runbook
    )
    assert '--arg document_digest "$COORDINATES_DOCUMENT_DIGEST"' in runbook
    assert (
        "terraform -chdir=terraform/bootstrap init \\\n"
        "  -migrate-state \\\n"
        "  -force-copy \\\n"
        "  -input=false"
        in migration
    )
    assert "-migrate-state \\\n  -input=false" not in migration


def test_runbook_uses_protected_windows_jump_host_evidence_transfer() -> None:
    runbook = (ROOT / "docs/quickstart-evidence-runbook.md").read_text()
    transfer = runbook.split(
        "## B8.1 Transfer node evidence through the Windows jump host", 1
    )[1].split("## B9.", 1)[0]

    assert 'INCOMING_ROOT="$DEMO_STATE_DIR/incoming"' in transfer
    assert "az network bastion tunnel" not in transfer
    assert "direct SSH or SCP tunnel" in transfer
    assert "$PrivateAddress" in transfer
    assert "scp -i $PrivateKey" in transfer
    assert "grep -Eq '(^/|(^|/)\\.\\.(/|$))'" in transfer
    assert "sha256sum -c MANIFEST.sha256" in transfer
    assert 'test "$INCOMING_SECRET_SCAN_STATUS" -eq 1' in transfer
    assert "Do not use the Terraform `tfstate` container" in transfer
    assert "private-administration.json" in transfer
    assert "approved native RDP client" in transfer
    assert "protected-drive redirection" in transfer
    assert "install -m 0600" in transfer
    assert "copy them directly into `/evidence`" in runbook


def test_runbook_persists_only_protected_run_context() -> None:
    runbook = (ROOT / "docs/quickstart-evidence-runbook.md").read_text()
    helper = runbook.split("persist_run_context() {", 1)[1].split("```", 1)[0]

    assert 'RUN_CONTEXT_DIR="/state/evidence-runs/$RUN_ID"' in helper
    assert 'printf "export ' not in helper
    assert "printf 'export RUN_ID=%q\\n'" in helper
    assert "declare -f persist_run_context" in helper
    assert 'chmod 0600 "$temporary_file"' in helper
    assert 'test ! -L "$RUN_CONTEXT_FILE"' in helper
    assert 'stat -c \'%u\'' in helper
    assert runbook.count("persist_run_context\n") >= 6
    assert 'source "$RUN_CONTEXT_FILE"' in runbook
    assert 'bash -n "$RUN_CONTEXT_FILE"' in runbook
    for forbidden in (
        "access_token",
        "account_key",
        "client_secret",
        "password",
        "sas_token",
    ):
        assert forbidden not in helper.lower()


def test_migration_contract_records_digest_only_disposition() -> None:
    schema = _schemas()[0]["backend-migration-acceptance.schema.json"]
    local_properties = schema["properties"]["local_state"]["properties"]
    assert "digest" in local_properties
    assert "content" not in local_properties
    assert "retained_until_verified" in local_properties
    assert "named_files_absent_after_deletion" in local_properties
