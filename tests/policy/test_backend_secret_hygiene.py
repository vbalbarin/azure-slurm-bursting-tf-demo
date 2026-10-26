from __future__ import annotations

import json
from pathlib import Path
import subprocess


ROOT = Path(__file__).parents[2]
CONTRACTS = ROOT / "specs/003-terraform-backend-bootstrap/contracts"
PASSWORD_EVIDENCE_SCHEMA = (
    ROOT
    / "specs/004-user-friendly-passwords/contracts/credential-evidence.schema.json"
)
CHEF_BOOTSTRAP_CONTRACTS = (
    ROOT / "specs/005-automated-chef-bootstrap/contracts"
)
PROTECTED_SUFFIXES = (".tfstate", ".tfplan")
PROTECTED_NAMES = {
    "backend.local.tf",
    "backend.azurerm.tf",
    "backend-readiness.json",
    "backend-readiness-assertions.json",
    "backend-plan-approval.json",
    "backend-lifecycle.json",
    "backend-migration-acceptance.json",
    "backend-live-acceptance.json",
}
SECRET_FIELD_NAMES = {
    "access_token",
    "account_key",
    "client_secret",
    "password",
    "refresh_token",
    "sas_token",
}
PASSWORD_DERIVED_FIELD_NAMES = {
    "character_positions",
    "encoded_value",
    "hash",
    "password",
    "prefix",
    "suffix",
    "value",
}


def _tracked_paths() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files", "-z"],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [item.decode() for item in result.stdout.split(b"\0") if item]


def _schema_property_names(value: object) -> set[str]:
    if isinstance(value, dict):
        names = set(value.get("properties", {}))
        for child in value.values():
            names.update(_schema_property_names(child))
        return names
    if isinstance(value, list):
        names: set[str] = set()
        for child in value:
            names.update(_schema_property_names(child))
        return names
    return set()


def test_no_protected_backend_artifacts_are_tracked() -> None:
    violations = []
    for tracked in _tracked_paths():
        name = Path(tracked).name
        if name in PROTECTED_NAMES or name.endswith(PROTECTED_SUFFIXES):
            violations.append(tracked)
    assert violations == []


def test_backend_contracts_cannot_accept_secret_fields() -> None:
    for schema_path in CONTRACTS.glob("backend-*.schema.json"):
        schema = json.loads(schema_path.read_text())
        assert schema.get("additionalProperties") is False
        assert _schema_property_names(schema).isdisjoint(SECRET_FIELD_NAMES)


def test_password_evidence_contract_cannot_accept_values_or_derivatives() -> None:
    schema = json.loads(PASSWORD_EVIDENCE_SCHEMA.read_text())
    assert schema.get("additionalProperties") is False
    assert _schema_property_names(schema).isdisjoint(
        SECRET_FIELD_NAMES | PASSWORD_DERIVED_FIELD_NAMES
    )


def test_chef_bootstrap_contracts_cannot_accept_secret_values() -> None:
    forbidden = SECRET_FIELD_NAMES | {
        "private_key",
        "raw_password",
        "accessToken",
        "refreshToken",
        "secretValue",
    }
    for schema_path in CHEF_BOOTSTRAP_CONTRACTS.glob("*.schema.json"):
        schema = json.loads(schema_path.read_text())
        assert schema.get("additionalProperties") is False
        assert _schema_property_names(schema).isdisjoint(forbidden)


def test_chef_workflows_keep_protected_values_transient_and_evidence_value_free() -> None:
    scheduler = (ROOT / "chef/bin/converge-scheduler.sh").read_text()
    retriever = (ROOT / "chef/bin/retrieve-key-vault-secret.py").read_text()
    dispatcher = (ROOT / "tests/end-to-end/converge_linux_roles.sh").read_text()
    state_tool = (ROOT / "chef/bin/convergence_state.py").read_text()

    assert "set +x" in scheduler
    assert "trap cleanup EXIT" in scheduler
    assert 'runtime_dir=/run/slurm-demo' in scheduler
    assert 'rm -f "$secret_file"' in scheduler
    assert "os.O_EXCL, 0o600" in retriever
    assert "os.chmod(path, 0o600)" in retriever
    assert "path.unlink(missing_ok=True)" in retriever
    assert "secret-access-passed" in dispatcher
    assert "cat \"$p\"" not in dispatcher
    assert "commandLine" not in state_tool
    assert "stdout" not in state_tool
    assert "stderr" not in state_tool
    assert "privateKey" not in state_tool


def test_protected_artifact_patterns_are_ignored_everywhere() -> None:
    required = {
        "**/backend.local.tf",
        "**/backend.azurerm.tf",
        "**/backend-readiness.json",
        "**/backend-plan-approval.json",
        "*.tfplan",
        "*.tfstate",
    }
    for ignore_name in (".gitignore", ".dockerignore", ".terraformignore"):
        entries = {
            line.strip()
            for line in (ROOT / ignore_name).read_text().splitlines()
            if line.strip() and not line.startswith("#")
        }
        missing = {
            pattern
            for pattern in required
            if pattern not in entries
            and not (pattern == "*.tfstate" and "*.tfstate*" in entries)
        }
        assert missing == set(), f"{ignore_name} lacks {sorted(missing)}"
