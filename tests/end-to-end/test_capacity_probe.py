from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
SCRIPT = REPOSITORY_ROOT / "tests/end-to-end/capacity_probe.sh"
PROBE_CONFIGURATION = REPOSITORY_ROOT / "terraform/capacity-probe/main.tf"


def _write_fake_terraform(directory: Path) -> None:
    executable = directory / "terraform"
    executable.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys
import time

args = sys.argv[1:]
with Path(os.environ["FAKE_TERRAFORM_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
command = next(arg for arg in args if not arg.startswith("-chdir="))

if command in {"fmt", "validate"}:
    pass
elif command == "plan":
    output = next(arg.split("=", 1)[1] for arg in args if arg.startswith("-out="))
    Path(output).write_bytes(b"fake-plan")
elif command == "show":
    print(os.environ.get("FAKE_PLAN_SECRET", "{}"))
elif command == "apply":
    if os.environ.get("FAKE_APPLY_SLEEP"):
        time.sleep(float(os.environ["FAKE_APPLY_SLEEP"]))
    if os.environ.get("FAKE_APPLY_ERROR"):
        print(os.environ["FAKE_APPLY_ERROR"], file=sys.stderr)
        sys.exit(1)
elif command == "output":
    print(json.dumps({
        "resource_group_name": "probe-rg",
        "virtual_machine_id": "/subscriptions/demo/vm/probe",
        "region": "southcentralus",
        "zone": "1",
        "vm_size": "Standard_HB120rs_v3",
        "image_urn": "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110",
        "expires_at": "2026-10-09T15:00:00Z",
        "guarantee": "point_in_time_only",
    }))
elif command == "state":
    if os.environ.get("FAKE_STATE_REMAINS"):
        print("module.virtual_machine.azurerm_linux_virtual_machine.this[0]")
else:
    print(f"Unexpected terraform invocation: {args}", file=sys.stderr)
    sys.exit(9)
"""
    )
    executable.chmod(0o755)


def _environment(tmp_path: Path) -> dict[str, str]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_terraform(fake_bin)
    tfvars = tmp_path / "probe.tfvars"
    tfvars.write_text("cost_acknowledged = true\n")
    evidence = tmp_path / "evidence"
    return {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "FAKE_TERRAFORM_LOG": str(tmp_path / "terraform.log"),
        "PROBE_TFVARS_FILE": str(tfvars),
        "PROBE_PLAN_FILE": str(tmp_path / "probe.tfplan"),
        "PROBE_APPROVAL_FILE": str(tmp_path / "probe-approval.json"),
        "PROBE_DESTROY_PLAN_FILE": str(tmp_path / "probe-destroy.tfplan"),
        "PROBE_CLEANUP_APPROVAL_FILE": str(
            tmp_path / "probe-cleanup-approval.json"
        ),
        "PROBE_EVIDENCE_DIR": str(evidence),
        "PROBE_TIMEOUT_SECONDS": "5",
    }


def _run(environment: dict[str, str], action: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(SCRIPT), action],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )


def _approve(plan: Path, approval: Path) -> None:
    approval.write_text(
        json.dumps(
            {
                "plan_digest": hashlib.sha256(plan.read_bytes()).hexdigest(),
                "cost_acknowledged": True,
                "approval_reference": "review-123",
            }
        )
    )


def test_probe_configuration_includes_burst_image_marketplace_plan() -> None:
    configuration = PROBE_CONFIGURATION.read_text()

    assert """  plan = {
    name      = var.burst_compute_image.sku
    product   = var.burst_compute_image.offer
    publisher = var.burst_compute_image.publisher
  }""" in configuration


def test_probe_success_and_verified_cleanup(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    environment["FAKE_PLAN_SECRET"] = "-----BEGIN PRIVATE KEY-----"
    assert _run(environment, "plan").returncode == 0
    _approve(
        Path(environment["PROBE_PLAN_FILE"]),
        Path(environment["PROBE_APPROVAL_FILE"]),
    )
    assert _run(environment, "apply").returncode == 0
    assert _run(environment, "cleanup-plan").returncode == 0
    _approve(
        Path(environment["PROBE_DESTROY_PLAN_FILE"]),
        Path(environment["PROBE_CLEANUP_APPROVAL_FILE"]),
    )
    assert _run(environment, "cleanup").returncode == 0

    evidence = json.loads(
        (Path(environment["PROBE_EVIDENCE_DIR"]) / "capacity-probe.json").read_text()
    )
    assert evidence["allocation_state"] == "allocated"
    assert evidence["cleanup_state"] == "verified"
    assert evidence["guarantee"] == "point_in_time_only"
    assert not (
        Path(environment["PROBE_EVIDENCE_DIR"]) / "probe-plan.json"
    ).exists()
    assert not (
        Path(environment["PROBE_EVIDENCE_DIR"]) / "probe-destroy-plan.json"
    ).exists()
    assert all(
        environment["FAKE_PLAN_SECRET"] not in path.read_text()
        for path in Path(environment["PROBE_EVIDENCE_DIR"]).iterdir()
        if path.is_file()
    )


def test_probe_classifies_allocation_failure(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    assert _run(environment, "plan").returncode == 0
    _approve(
        Path(environment["PROBE_PLAN_FILE"]),
        Path(environment["PROBE_APPROVAL_FILE"]),
    )
    environment["FAKE_APPLY_ERROR"] = "AllocationFailed"

    assert _run(environment, "apply").returncode != 0
    evidence = json.loads(
        (Path(environment["PROBE_EVIDENCE_DIR"]) / "capacity-probe.json").read_text()
    )
    assert evidence["failure_class"] == "allocation_failed"
    assert evidence["cleanup_state"] == "pending"


def test_probe_timeout_is_inconclusive(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    environment["PROBE_TIMEOUT_SECONDS"] = "1"
    assert _run(environment, "plan").returncode == 0
    _approve(
        Path(environment["PROBE_PLAN_FILE"]),
        Path(environment["PROBE_APPROVAL_FILE"]),
    )
    environment["FAKE_APPLY_SLEEP"] = "2"

    assert _run(environment, "apply").returncode == 124
    evidence = json.loads(
        (Path(environment["PROBE_EVIDENCE_DIR"]) / "capacity-probe.json").read_text()
    )
    assert evidence["failure_class"] == "timed_out"


def test_cleanup_fails_when_state_remains(tmp_path: Path) -> None:
    environment = _environment(tmp_path)
    assert _run(environment, "plan").returncode == 0
    _approve(
        Path(environment["PROBE_PLAN_FILE"]),
        Path(environment["PROBE_APPROVAL_FILE"]),
    )
    assert _run(environment, "apply").returncode == 0
    assert _run(environment, "cleanup-plan").returncode == 0
    _approve(
        Path(environment["PROBE_DESTROY_PLAN_FILE"]),
        Path(environment["PROBE_CLEANUP_APPROVAL_FILE"]),
    )
    environment["FAKE_STATE_REMAINS"] = "1"

    result = _run(environment, "cleanup")
    assert result.returncode == 12
    assert "cleanup could not be verified" in result.stderr
