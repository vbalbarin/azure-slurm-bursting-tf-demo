from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
PREFLIGHT = REPOSITORY_ROOT / "tests/end-to-end/preflight.sh"


def _write_fake_az(directory: Path) -> None:
    executable = directory / "az"
    executable.write_text(
        """#!/usr/bin/env python3
import json
import os
import sys

args = sys.argv[1:]
query = args[args.index("--query") + 1] if "--query" in args else ""

if args[:2] == ["account", "show"]:
    print(json.dumps({
        "subscriptionId": "00000000-0000-0000-0000-000000000000",
        "tenantId": "11111111-1111-1111-1111-111111111111",
    }))
elif args[:1] == ["rest"]:
    if os.environ.get("FAKE_GRAPH_DENIED"):
        print("Graph request denied", file=sys.stderr)
        sys.exit(1)
    response = os.environ.get("FAKE_GRAPH_RESPONSE")
    if response is None:
        response = json.dumps({
            "value": [{
                "capabilityStatus": "Enabled",
                "servicePlans": [{
                    "servicePlanName": "AAD_PREMIUM",
                    "provisioningStatus": "Success",
                }],
            }],
        })
    print(response)
elif args[:2] == ["account", "list-locations"]:
    print("eastus")
    print("southcentralus")
    print("eastus2")
elif args[:2] == ["vm", "list-skus"]:
    size = args[args.index("--size") + 1]
    region = args[args.index("--location") + 1]
    if region == os.environ.get("FAKE_MISSING_SKU_REGION"):
        sys.exit(0)
    role = "BURST" if size == "Standard_HB120rs_v3" else "SCHEDULER"
    family = "standardHBSFamily" if role == "BURST" else "standardDSv6Family"
    zones = os.environ.get(f"FAKE_{role}_ZONES", "1,2,3").split(",")
    restrictions = json.loads(
        os.environ.get(f"FAKE_{role}_RESTRICTIONS", "[]")
    )
    print(json.dumps({
        "name": size,
        "family": family,
        "restrictions": restrictions,
        "locationInfo": [{
            "location": args[args.index("--location") + 1],
            "zones": zones,
        }],
        "capabilities": [
            {
                "name": "vCPUs",
                "value": "120" if role == "BURST" else (
                    "2" if size == "Standard_D2s_v6" else "4"
                ),
            },
            {
                "name": "HyperVGenerations",
                "value": os.environ.get(f"FAKE_{role}_SIZE_HYPERV", "V2"),
            },
            {
                "name": "CpuArchitectureType",
                "value": os.environ.get(f"FAKE_{role}_SIZE_ARCH", "x64"),
            },
        ],
    }))
elif args[:2] == ["vm", "list-usage"]:
    region = args[args.index("--location") + 1]
    usages = [
        {
            "name": {"value": "cores"},
            "currentValue": "0",
            "limit": os.environ.get("FAKE_REGIONAL_QUOTA_LIMIT", "1000"),
        },
        {
            "name": {"value": "standardDSv6Family"},
            "currentValue": "0",
            "limit": os.environ.get("FAKE_DSV6_QUOTA_LIMIT", "1000"),
        },
    ]
    if not (
        region == "eastus2"
        and os.environ.get("FAKE_ALTERNATE_OMIT_HB_QUOTA")
    ):
        usages.append({
            "name": {"value": "standardHBSFamily"},
            "currentValue": "0",
            "limit": os.environ.get("FAKE_HB_QUOTA_LIMIT", "1000"),
        })
    print(json.dumps(usages))
elif args[:3] == ["vm", "image", "show"]:
    urn = ":".join(
        args[args.index(option) + 1]
        for option in ("--publisher", "--offer", "--sku", "--version")
    )
    if urn == os.environ.get("FAKE_MISSING_URN"):
        sys.exit(3)
    role = "BURST" if ":almalinux-hpc:" in urn else "SCHEDULER"
    if args[args.index("--output") + 1] != "none":
        print(json.dumps({
            "hyperVGeneration": os.environ.get(
                f"FAKE_{role}_IMAGE_HYPERV", "V2"
            ),
            "architecture": os.environ.get(f"FAKE_{role}_IMAGE_ARCH", "x64"),
        }))
elif args[:3] == ["vm", "image", "terms"]:
    if query != "accepted":
        print("false")
    else:
        print(os.environ.get("FAKE_MARKETPLACE_TERMS_ACCEPTED", "true"))
else:
    print(f"Unexpected az invocation: {args}", file=sys.stderr)
    sys.exit(9)
"""
    )
    executable.chmod(0o755)


def _environment(tmp_path: Path) -> dict[str, str]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_fake_az(fake_bin)
    return {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "SOURCE_REGION": "eastus",
        "BURST_REGION": "southcentralus",
        "BURST_ZONE": "1",
        "ALTERNATE_BURST_PLACEMENTS_JSON": (
            '[{"region":"eastus2","zone":"1"}]'
        ),
        "CYCLECLOUD_VM_SIZE": "Standard_D4s_v6",
        "SCHEDULER_VM_SIZE": "Standard_D4s_v6",
        "WINDOWS_VM_SIZE": "Standard_D2s_v6",
        "BURST_VM_SIZE": "Standard_HB120rs_v3",
        "CYCLECLOUD_URN": (
            "azurecyclecloud:azure-cyclecloud:"
            "cyclecloud8-gen2:8.9.320260827"
        ),
        "SCHEDULER_URN": (
            "almalinux:almalinux-x86_64:9-gen2:9.8.2026100501"
        ),
        "BURST_COMPUTE_URN": (
            "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
        ),
        "WINDOWS_URN": (
            "MicrosoftWindowsServer:WindowsServer:"
            "2025-datacenter-azure-edition:26100.33438.260905"
        ),
    }


def _run(tmp_path: Path, **overrides: str) -> subprocess.CompletedProcess[str]:
    environment = _environment(tmp_path)
    environment.update(overrides)
    return subprocess.run(
        [str(PREFLIGHT)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )


def test_records_role_specific_image_compatibility(tmp_path: Path) -> None:
    result = _run(tmp_path)

    assert result.returncode == 0, result.stderr
    evidence = json.loads(result.stdout)
    assert evidence["images"]["scheduler"]["urn"].endswith("9.8.2026100501")
    assert evidence["images"]["burst_compute"]["urn"].endswith("9.8.202608110")
    assert evidence["images"]["compatibility"] == {
        "architecture": "x64",
        "hyperv_generation": "V2",
        "os_family": "almalinux",
        "os_major": "9",
        "status": "validated",
    }
    assert evidence["capacity"]["status"] == "validated"
    assert evidence["capacity"]["roles"]["burst_compute"]["zone"] == "1"
    assert evidence["capacity"]["roles"]["burst_compute"]["family_quota"][
        "required"
    ] == 120
    assert evidence["capacity"]["alternate_placements"][0]["status"] == "eligible"


def test_records_value_free_entra_p1_receipt(tmp_path: Path) -> None:
    graph_response = json.dumps({
        "value": [{
            "capabilityStatus": "Enabled",
            "skuId": "must-not-be-recorded",
            "servicePlans": [{
                "servicePlanId": "must-not-be-recorded",
                "servicePlanName": "AAD_PREMIUM",
                "provisioningStatus": "Success",
            }],
        }],
    })

    result = _run(tmp_path, FAKE_GRAPH_RESPONSE=graph_response)

    assert result.returncode == 0, result.stderr
    evidence = json.loads(result.stdout)
    receipt = evidence["entraP1"]
    assert set(receipt) == {
        "schemaVersion",
        "tenantId",
        "checkedAt",
        "result",
        "detailCode",
    }
    assert receipt["schemaVersion"] == 1
    assert receipt["tenantId"] == "11111111-1111-1111-1111-111111111111"
    assert receipt["checkedAt"].endswith("Z")
    assert receipt["result"] == "passed"
    assert receipt["detailCode"] == "entra_p1_verified"
    assert "must-not-be-recorded" not in result.stdout


def test_rejects_denied_graph_query_with_value_free_receipt(
    tmp_path: Path,
) -> None:
    result = _run(tmp_path, FAKE_GRAPH_DENIED="1")

    assert result.returncode == 8
    assert json.loads(result.stdout) == {
        "schemaVersion": 1,
        "tenantId": "11111111-1111-1111-1111-111111111111",
        "checkedAt": json.loads(result.stdout)["checkedAt"],
        "result": "failed",
        "detailCode": "entra_p1_graph_query_denied",
    }
    assert "subscribedSkus query was denied or failed" in result.stderr


def test_rejects_ambiguous_graph_response(tmp_path: Path) -> None:
    ambiguous = json.dumps({
        "value": [{
            "capabilityStatus": "Enabled",
            "servicePlans": [{
                "servicePlanName": "AAD_PREMIUM",
            }],
        }],
    })

    result = _run(tmp_path, FAKE_GRAPH_RESPONSE=ambiguous)

    assert result.returncode == 8
    receipt = json.loads(result.stdout)
    assert receipt["result"] == "failed"
    assert receipt["detailCode"] == "entra_p1_response_ambiguous"
    assert set(receipt) == {
        "schemaVersion",
        "tenantId",
        "checkedAt",
        "result",
        "detailCode",
    }


def test_rejects_unavailable_entra_p1_plan(tmp_path: Path) -> None:
    unavailable = json.dumps({
        "value": [{
            "capabilityStatus": "Enabled",
            "servicePlans": [{
                "servicePlanName": "AAD_PREMIUM",
                "provisioningStatus": "Disabled",
            }],
        }],
    })

    result = _run(tmp_path, FAKE_GRAPH_RESPONSE=unavailable)

    assert result.returncode == 8
    receipt = json.loads(result.stdout)
    assert receipt["result"] == "failed"
    assert receipt["detailCode"] == "entra_p1_not_available"


def test_rejects_unavailable_burst_image(tmp_path: Path) -> None:
    missing = "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
    result = _run(tmp_path, FAKE_MISSING_URN=missing)

    assert result.returncode != 0


def test_rejects_unaccepted_cyclecloud_marketplace_terms(tmp_path: Path) -> None:
    result = _run(tmp_path, FAKE_MARKETPLACE_TERMS_ACCEPTED="false")

    assert result.returncode == 5
    assert "Marketplace terms are not accepted" in result.stderr


def test_rejects_incompatible_os_major(tmp_path: Path) -> None:
    result = _run(
        tmp_path,
        BURST_COMPUTE_URN=(
            "almalinux:almalinux-hpc:10-hpc-gen2:10.0.202610010"
        ),
    )

    assert result.returncode != 0
    assert "operating-system major" in result.stderr


def test_rejects_image_size_generation_mismatch(tmp_path: Path) -> None:
    result = _run(tmp_path, FAKE_BURST_SIZE_HYPERV="V1")

    assert result.returncode != 0
    assert "Hyper-V generation" in result.stderr


def test_rejects_insufficient_burst_family_quota(tmp_path: Path) -> None:
    result = _run(tmp_path, FAKE_HB_QUOTA_LIMIT="119")

    assert result.returncode != 0
    evidence = json.loads(result.stdout)
    assert evidence["capacity"]["roles"]["burst_compute"]["failure_class"] == (
        "family_quota_insufficient"
    )


def test_rejects_insufficient_regional_quota(tmp_path: Path) -> None:
    result = _run(tmp_path, FAKE_REGIONAL_QUOTA_LIMIT="119")

    assert result.returncode != 0
    evidence = json.loads(result.stdout)
    assert evidence["capacity"]["roles"]["burst_compute"]["failure_class"] == (
        "regional_quota_insufficient"
    )


def test_rejects_unavailable_burst_zone(tmp_path: Path) -> None:
    result = _run(tmp_path, FAKE_BURST_ZONES="2,3")

    assert result.returncode != 0
    evidence = json.loads(result.stdout)
    assert evidence["capacity"]["roles"]["burst_compute"]["failure_class"] == (
        "zonal_restriction"
    )


def test_rejects_subscription_restriction(tmp_path: Path) -> None:
    restriction = json.dumps(
        [{"type": "Location", "reasonCode": "NotAvailableForSubscription"}]
    )
    result = _run(tmp_path, FAKE_BURST_RESTRICTIONS=restriction)

    assert result.returncode != 0
    evidence = json.loads(result.stdout)
    assert evidence["capacity"]["roles"]["burst_compute"]["failure_class"] == (
        "subscription_restriction"
    )


def test_reports_alternate_with_missing_quota_as_inconclusive(
    tmp_path: Path,
) -> None:
    result = _run(tmp_path, FAKE_ALTERNATE_OMIT_HB_QUOTA="1")

    assert result.returncode == 0, result.stderr
    evidence = json.loads(result.stdout)
    alternate = evidence["capacity"]["alternate_placements"][0]
    assert alternate["status"] == "inconclusive"
    assert alternate["failure_class"] == "family_quota_unavailable"


def test_reports_unavailable_alternate_sku_without_failing_selection(
    tmp_path: Path,
) -> None:
    result = _run(tmp_path, FAKE_MISSING_SKU_REGION="eastus2")

    assert result.returncode == 0, result.stderr
    evidence = json.loads(result.stdout)
    alternate = evidence["capacity"]["alternate_placements"][0]
    assert alternate["status"] == "ineligible"
    assert alternate["failure_class"] == "sku_unavailable"
