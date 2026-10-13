from __future__ import annotations

import json
from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
SCRIPT = REPOSITORY_ROOT / "tests/end-to-end/render_preflight_summary.sh"


def _preflight() -> dict[str, object]:
    quota = {
        "name": "cores",
        "current": 0,
        "limit": 100,
        "required": 10,
        "available": 100,
        "projected_remaining": 90,
    }
    return {
        "subscription_id": "00000000-0000-0000-0000-000000000000",
        "source_region": "eastus",
        "burst_region": "southcentralus",
        "burst_zone": "1",
        "cyclecloud_version": "8.9.3",
        "burst_vm_size": "Standard_HB120rs_v3",
        "images": {
            "scheduler": {"urn": "scheduler:image:urn:1"},
            "burst_compute": {"urn": "burst:image:urn:1"},
            "compatibility": {
                "status": "validated",
                "os_family": "almalinux",
                "os_major": "9",
                "hyperv_generation": "V2",
                "architecture": "x64",
            },
        },
        "capacity": {
            "status": "validated",
            "assessed_at": "2026-10-13T14:15:43Z",
            "roles": {
                "cyclecloud": {
                    "region": "eastus",
                    "zone": "",
                    "vm_size": "Standard_D4s_v6",
                    "vm_family": "StandardDsv6Family",
                    "planned_count": 1,
                    "vcpus_per_vm": 4,
                    "zones": ["1", "2", "3"],
                    "restrictions": [],
                    "regional_quota": quota,
                    "family_quota": {
                        **quota,
                        "name": "StandardDsv6Family",
                    },
                    "status": "eligible",
                    "failure_class": "none",
                }
            },
            "alternate_placements": [],
            "probe_status": "not_run",
            "disclaimer": "Static checks do not guarantee allocation.",
        },
        "global_peering": "validated during reviewed Terraform plan",
    }


def _run(tmp_path: Path, evidence: dict[str, object]) -> subprocess.CompletedProcess[str]:
    source = tmp_path / "preflight.json"
    source.write_text(json.dumps(evidence))
    return subprocess.run(
        [str(SCRIPT), str(source)],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )


def test_renders_validated_preflight_as_markdown(tmp_path: Path) -> None:
    result = _run(tmp_path, _preflight())

    assert result.returncode == 0, result.stderr
    assert result.stdout.startswith("# Azure Preflight Summary\n")
    assert "| Overall capacity status | validated |" in result.stdout
    assert "| CycleCloud | eligible | none | eastus | n/a |" in result.stdout
    assert "| CycleCloud | Regional | cores | 0 | 100 | 10 | 100 | 90 |" in (
        result.stdout
    )
    assert "## Blocking Findings\n\n- None." in result.stdout


def test_lists_every_burst_blocker(tmp_path: Path) -> None:
    evidence = _preflight()
    capacity = evidence["capacity"]
    assert isinstance(capacity, dict)
    capacity["status"] = "failed"
    roles = capacity["roles"]
    assert isinstance(roles, dict)
    roles["burst_compute"] = {
        "region": "southcentralus",
        "zone": "1",
        "vm_size": "Standard_HB120rs_v3",
        "vm_family": "standardHBv3Family",
        "planned_count": 1,
        "vcpus_per_vm": 120,
        "zones": ["3"],
        "restrictions": [
            {
                "type": "Location",
                "reasonCode": "NotAvailableForSubscription",
                "restrictionInfo": {"locations": ["southcentralus"]},
            }
        ],
        "regional_quota": {
            "name": "cores",
            "current": 0,
            "limit": 100,
            "required": 120,
            "available": 100,
            "projected_remaining": -20,
        },
        "family_quota": {
            "name": "standardHBv3Family",
            "current": 0,
            "limit": 0,
            "required": 120,
            "available": 0,
            "projected_remaining": -120,
        },
        "status": "ineligible",
        "failure_class": "regional_quota_insufficient",
    }
    capacity["alternate_placements"] = [
        {
            "region": "northcentralus",
            "zone": "1",
            "vm_size": "Standard_HB120rs_v3",
            "status": "ineligible",
            "failure_class": "sku_unavailable",
            "image_status": "available",
        }
    ]

    result = _run(tmp_path, evidence)

    assert result.returncode == 0, result.stderr
    assert "selects zone `1`, but Azure reports available zones `3`" in result.stdout
    assert "Location: NotAvailableForSubscription (southcentralus)" in result.stdout
    assert "insufficient regional quota: 100 available and 120 required" in (
        result.stdout
    )
    assert "insufficient VM-family quota: 0 available and 120 required" in (
        result.stdout
    )
    assert "Alternate `northcentralus` zone `1` is `ineligible`" in result.stdout


def test_rejects_unexpected_schema(tmp_path: Path) -> None:
    result = _run(tmp_path, {"capacity": {"status": "failed"}})

    assert result.returncode == 3
    assert "expected schema" in result.stderr
