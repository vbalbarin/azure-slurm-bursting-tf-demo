from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess


ROOT = Path(__file__).parents[2]
SCRIPT = ROOT / "tests/end-to-end/key_vault_reconciliation.sh"
VAULT_ADDRESS = "module.key_vault.azurerm_key_vault.this"


def _vault_change(actions: list[str]) -> dict[str, object]:
    return {
        "address": VAULT_ADDRESS,
        "change": {
            "actions": actions,
            "after": {
                "name": "demo-kv",
                "resource_group_name": "demo-rg",
                "public_network_access_enabled": True,
                "network_acls": [
                    {
                        "bypass": "None",
                        "default_action": "Deny",
                        "ip_rules": ["203.0.113.10/32"],
                        "virtual_network_subnet_ids": [],
                    }
                ],
                "tags": {"SecurityControl": "Ignore"},
            },
        },
    }


def _write_fake_commands(directory: Path) -> None:
    terraform = directory / "terraform"
    terraform.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import shutil
import sys

args = sys.argv[1:]
command = next(arg for arg in args if not arg.startswith("-chdir="))
with Path(os.environ["FAKE_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
if command == "show":
    print(Path(args[-1]).read_text())
elif command == "plan":
    output = next(arg.split("=", 1)[1] for arg in args if arg.startswith("-out="))
    shutil.copyfile(os.environ["FAKE_RECONCILIATION_PLAN"], output)
elif command == "apply":
    Path(os.environ["FAKE_APPLIED"]).touch()
else:
    raise SystemExit(9)
"""
    )
    terraform.chmod(0o755)

    az = directory / "az"
    az.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

if sys.argv[1:3] == ["keyvault", "show"]:
    matched = os.environ.get("FAKE_LIVE_MATCH") == "true" or Path(
        os.environ["FAKE_APPLIED"]
    ).exists()
    print(json.dumps({
        "publicNetworkAccess": "Enabled" if matched else "Disabled",
        "defaultAction": "Deny",
        "ipRules": ["203.0.113.10/32"] if matched else [],
        "securityControl": "Ignore",
    }))
elif sys.argv[1:3] == ["group", "show"]:
    print("")
else:
    raise SystemExit(9)
"""
    )
    az.chmod(0o755)


def _environment(tmp_path: Path, *, live_matches: bool = False) -> dict[str, str]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_commands(fake_bin)

    foundation = tmp_path / "foundation.tfplan"
    foundation.write_text(json.dumps({"resource_changes": [_vault_change(["create"])]}))
    reconciliation = tmp_path / "reconciliation-source.json"
    reconciliation.write_text(
        json.dumps({"resource_changes": [_vault_change(["update"])]})
    )
    tfvars = tmp_path / "demo.tfvars"
    tfvars.write_text('environment_name = "demo"\n')

    return {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "FAKE_LOG": str(tmp_path / "terraform.log"),
        "FAKE_APPLIED": str(tmp_path / "applied"),
        "FAKE_LIVE_MATCH": str(live_matches).lower(),
        "FAKE_RECONCILIATION_PLAN": str(reconciliation),
        "TFVARS_FILE": str(tfvars),
        "FOUNDATION_PLAN_FILE": str(foundation),
        "KEY_VAULT_RECONCILIATION_PLAN_FILE": str(tmp_path / "reconcile.tfplan"),
        "KEY_VAULT_RECONCILIATION_APPROVAL_FILE": str(tmp_path / "approval.json"),
        "KEY_VAULT_PROVISIONING_EVIDENCE_FILE": str(tmp_path / "posture.json"),
    }


def _run(action: str, environment: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT), action],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )


def test_check_accepts_exact_live_provisioning_posture(tmp_path: Path) -> None:
    environment = _environment(tmp_path, live_matches=True)

    result = _run("check", environment)

    assert result.returncode == 0, result.stderr
    evidence = json.loads(
        Path(environment["KEY_VAULT_PROVISIONING_EVIDENCE_FILE"]).read_text()
    )
    assert evidence["status"] == "matched"
    assert evidence["reconciliationApplied"] is False


def test_check_requires_reconciliation_for_recovered_private_posture(
    tmp_path: Path,
) -> None:
    environment = _environment(tmp_path)

    result = _run("check", environment)

    assert result.returncode == 20
    assert "reconciliation is required" in result.stderr
    evidence = json.loads(
        Path(environment["KEY_VAULT_PROVISIONING_EVIDENCE_FILE"]).read_text()
    )
    assert evidence["status"] == "reconciliation_required"


def test_plan_rejects_any_non_key_vault_change(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    assert _run("check", environment).returncode == 20
    source_plan = Path(environment["FAKE_RECONCILIATION_PLAN"])
    content = json.loads(source_plan.read_text())
    content["resource_changes"].append(
        {
            "address": "module.resource_group.azurerm_resource_group.this",
            "change": {"actions": ["update"], "after": {}},
        }
    )
    source_plan.write_text(json.dumps(content))

    result = _run("plan", environment)

    assert result.returncode == 11
    assert "only the exact Key Vault" in result.stderr


def test_apply_requires_digest_approval_and_verifies_live_posture(
    tmp_path: Path,
) -> None:
    environment = _environment(tmp_path)
    assert _run("check", environment).returncode == 20
    plan_result = _run("plan", environment)
    assert plan_result.returncode == 0, plan_result.stderr
    plan = Path(environment["KEY_VAULT_RECONCILIATION_PLAN_FILE"])
    Path(environment["KEY_VAULT_RECONCILIATION_APPROVAL_FILE"]).write_text(
        json.dumps(
            {
                "plan_digest": hashlib.sha256(plan.read_bytes()).hexdigest(),
                "approval_reference": "review-456",
                "key_vault_policy_exclusion_approved": True,
            }
        )
    )

    result = _run("apply", environment)

    assert result.returncode == 0, result.stderr
    evidence = json.loads(
        Path(environment["KEY_VAULT_PROVISIONING_EVIDENCE_FILE"]).read_text()
    )
    assert evidence["status"] == "matched"
    assert evidence["reconciliationApplied"] is True
    assert evidence["approvalReference"] == "review-456"


def test_apply_rejects_an_unapproved_plan_digest(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    assert _run("check", environment).returncode == 20
    assert _run("plan", environment).returncode == 0
    Path(environment["KEY_VAULT_RECONCILIATION_APPROVAL_FILE"]).write_text(
        json.dumps(
            {
                "plan_digest": "0" * 64,
                "approval_reference": "review-789",
                "key_vault_policy_exclusion_approved": True,
            }
        )
    )

    result = _run("apply", environment)

    assert result.returncode == 11
    assert "Approved digest does not match" in result.stderr
    assert not Path(environment["FAKE_APPLIED"]).exists()
