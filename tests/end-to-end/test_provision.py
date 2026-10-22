from __future__ import annotations

from datetime import datetime, timedelta, timezone
import hashlib
import json
import os
from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
SCRIPT = REPOSITORY_ROOT / "tests/end-to-end/provision.sh"
BURST_IMAGE = "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
SCHEDULER_IMAGE = "almalinux:almalinux-x86_64:9-gen2:9.8.2026100501"


def _write_fake_terraform(directory: Path) -> None:
    executable = directory / "terraform"
    executable.write_text(
        f"""#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ["FAKE_TERRAFORM_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
command = next(arg for arg in args if not arg.startswith("-chdir="))
if command in {{"fmt", "validate", "apply"}}:
    pass
elif command == "plan":
    sys.exit(int(os.environ.get("FAKE_FOUNDATION_PLAN_STATUS", "0")))
elif command == "show":
    cidr = os.environ.get("FAKE_KEY_VAULT_CIDR", "32.216.31.25/32")
    public_access = os.environ.get("FAKE_KEY_VAULT_PUBLIC_ACCESS", "true") == "true"
    print(json.dumps({{
        "resource_changes": [{{
            "address": "module.key_vault.azurerm_key_vault.this",
            "change": {{
                "actions": ["create"],
                "after": {{
                    "public_network_access_enabled": public_access,
                    "network_acls": [{{
                        "default_action": "Deny",
                        "ip_rules": [cidr] if public_access else None
                    }}],
                    "tags": {{
                        "SecurityControl": "Ignore"
                    }} if public_access else {{}}
                }}
            }}
        }}]
    }}))
elif command == "output":
    print(json.dumps({{
        "environment_name": "demo",
        "source_region": "eastus",
        "burst_region": "southcentralus",
        "burst_zone": "1",
        "alternate_burst_placements": [],
        "planned_role_counts": {{
            "cyclecloud": 1,
            "scheduler": 1,
            "windows_admin": 1,
            "burst_compute": 1
        }},
        "cluster_name": "demo",
        "private_hosts": {{}},
        "versions": {{
            "scheduler_image": "{SCHEDULER_IMAGE}",
            "burst_compute_image": "{BURST_IMAGE}"
        }},
        "validation": {{}}
    }}))
else:
    print(f"Unexpected terraform invocation: {{args}}", file=sys.stderr)
    sys.exit(9)
"""
    )
    executable.chmod(0o755)


def _environment(tmp_path: Path) -> dict[str, str]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_terraform(fake_bin)
    evidence = tmp_path / "evidence"
    evidence.mkdir()
    plan = tmp_path / "reviewed.tfplan"
    plan.write_bytes(b"reviewed-plan")
    tfvars = tmp_path / "demo.tfvars"
    tfvars.write_text("environment_name = \"demo\"\n")
    assessed_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    preflight = tmp_path / "preflight.json"
    preflight.write_text(
        json.dumps(
            {
                "burst_region": "southcentralus",
                "burst_zone": "1",
                "images": {
                    "scheduler": {"urn": SCHEDULER_IMAGE},
                    "burst_compute": {"urn": BURST_IMAGE},
                    "compatibility": {"status": "validated"},
                },
                "capacity": {"status": "validated", "assessed_at": assessed_at},
            }
        )
    )
    probe = tmp_path / "capacity-probe.json"
    probe.write_text(
        json.dumps(
            {
                "region": "southcentralus",
                "zone": "1",
                "vm_size": "Standard_HB120rs_v3",
                "image_urn": BURST_IMAGE,
                "allocation_state": "allocated",
                "cleanup_state": "verified",
            }
        )
    )
    approval = tmp_path / "approval.json"
    approval.write_text(
        json.dumps(
            {
                "plan_digest": hashlib.sha256(plan.read_bytes()).hexdigest(),
                "preflight_digest": hashlib.sha256(
                    preflight.read_bytes()
                ).hexdigest(),
                "capacity_probe_digest": hashlib.sha256(
                    probe.read_bytes()
                ).hexdigest(),
                "approval_reference": "review-123",
                "key_vault_policy_exclusion_approved": True,
                "key_vault_provisioning_ipv4_cidr": "32.216.31.25/32",
            }
        )
    )
    return {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "FAKE_TERRAFORM_LOG": str(tmp_path / "terraform.log"),
        "TFVARS_FILE": str(tfvars),
        "PLAN_FILE": str(plan),
        "APPROVAL_FILE": str(approval),
        "PREFLIGHT_RESULTS_FILE": str(preflight),
        "CAPACITY_PROBE_RESULTS_FILE": str(probe),
        "EVIDENCE_DIR": str(evidence),
    }


def test_applies_reviewed_plan_then_requires_no_change(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    invocations = [
        json.loads(line)
        for line in Path(environment["FAKE_TERRAFORM_LOG"]).read_text().splitlines()
    ]
    assert any("apply" in invocation for invocation in invocations)
    assert any("plan" in invocation for invocation in invocations)
    assert (Path(environment["EVIDENCE_DIR"]) / "foundation-no-change.json").exists()


def test_rejects_post_apply_foundation_drift(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    environment["FAKE_FOUNDATION_PLAN_STATUS"] = "2"

    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 13
    assert "Post-foundation plan detected drift" in result.stderr
    evidence = json.loads(
        (Path(environment["EVIDENCE_DIR"]) / "foundation-no-change.json").read_text()
    )
    assert evidence["status"] == "failed"
    assert evidence["exit_code"] == 2
    assert not (Path(environment["EVIDENCE_DIR"]) / "inventory.json").exists()


def test_rejects_unapproved_plan_digest(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    approval = Path(environment["APPROVAL_FILE"])
    content = json.loads(approval.read_text())
    content["plan_digest"] = "0" * 64
    approval.write_text(json.dumps(content))

    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    invocations = Path(environment["FAKE_TERRAFORM_LOG"]).read_text()
    assert "apply" not in invocations


def test_rejects_unapproved_key_vault_policy_exclusion(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    approval = Path(environment["APPROVAL_FILE"])
    content = json.loads(approval.read_text())
    content["key_vault_policy_exclusion_approved"] = False
    approval.write_text(json.dumps(content))

    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "temporary Key Vault policy exclusion" in result.stderr
    invocations = Path(environment["FAKE_TERRAFORM_LOG"]).read_text()
    assert "apply" not in invocations


def test_rejects_private_key_vault_posture_in_foundation_plan(
    tmp_path: Path,
) -> None:
    environment = _environment(tmp_path)
    environment["FAKE_KEY_VAULT_PUBLIC_ACCESS"] = "false"

    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "exact approved Key Vault provisioning window" in result.stderr
    invocations = Path(environment["FAKE_TERRAFORM_LOG"]).read_text()
    assert "apply" not in invocations


def test_rejects_stale_preflight_evidence(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    preflight = Path(environment["PREFLIGHT_RESULTS_FILE"])
    content = json.loads(preflight.read_text())
    content["capacity"]["assessed_at"] = (
        datetime.now(timezone.utc) - timedelta(hours=2)
    ).strftime("%Y-%m-%dT%H:%M:%SZ")
    preflight.write_text(json.dumps(content))
    approval = Path(environment["APPROVAL_FILE"])
    approval_content = json.loads(approval.read_text())
    approval_content["preflight_digest"] = hashlib.sha256(
        preflight.read_bytes()
    ).hexdigest()
    approval.write_text(json.dumps(approval_content))

    result = subprocess.run(
        [str(SCRIPT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "stale" in result.stderr
    invocations = Path(environment["FAKE_TERRAFORM_LOG"]).read_text()
    assert "apply" not in invocations
