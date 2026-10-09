from __future__ import annotations

import importlib.util
from pathlib import Path

import pytest


MODULE_PATH = Path(__file__).with_name("verify_inventory.py")
SPEC = importlib.util.spec_from_file_location("verify_inventory", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
verify_inventory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(verify_inventory)


def _inventory() -> dict[str, object]:
    return {
        "environment_name": "demo",
        "source_region": "eastus",
        "burst_region": "southcentralus",
        "burst_zone": "1",
        "alternate_burst_placements": [{"region": "eastus2", "zone": "1"}],
        "planned_role_counts": {
            "cyclecloud": 1,
            "scheduler": 1,
            "windows_admin": 1,
            "burst_compute": 1,
        },
        "cluster_name": "demo-cluster",
        "private_hosts": {
            "cyclecloud": {"name": "cc", "private_address": "10.10.0.4"},
            "scheduler": {"name": "sched", "private_address": "10.10.0.5"},
            "windows_admin": {"name": "admin", "private_address": "10.10.0.6"},
        },
        "versions": {
            "cyclecloud": "8.9.3",
            "scheduler_image": (
                "almalinux:almalinux-x86_64:9-gen2:9.8.2026100501"
            ),
            "burst_compute_image": (
                "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
            ),
            "windows_image": (
                "MicrosoftWindowsServer:WindowsServer:"
                "2025-datacenter-azure-edition:26100.33438.260905"
            ),
        },
        "image_compatibility": {
            "status": "validated",
            "os_family": "almalinux",
            "os_major": "9",
        },
        "capacity_assessment": {
            "status": "validated",
            "assessed_at": "2026-10-09T13:00:00Z",
            "roles": {},
            "alternate_placements": [],
            "disclaimer": "Point-in-time evidence does not guarantee capacity.",
        },
        "capacity_probe": {
            "region": "southcentralus",
            "zone": "1",
            "vm_size": "Standard_HB120rs_v3",
            "image_urn": (
                "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
            ),
            "allocation_state": "allocated",
            "cleanup_state": "verified",
            "started_at": "2026-10-09T13:01:00Z",
            "completed_at": "2026-10-09T13:03:00Z",
            "cleaned_at": "2026-10-09T13:07:00Z",
            "guarantee": "point_in_time_only",
        },
        "validation": {
            "plan_digest": "a" * 64,
            "preflight_digest": "b" * 64,
            "capacity_probe_digest": "c" * 64,
            "approval_reference": "review-123",
        },
    }


def test_accepts_distinct_compatible_role_images() -> None:
    verify_inventory.validate(_inventory())


def test_rejects_missing_burst_compute_image() -> None:
    inventory = _inventory()
    versions = inventory["versions"]
    assert isinstance(versions, dict)
    del versions["burst_compute_image"]

    with pytest.raises(ValueError, match="role-specific image"):
        verify_inventory.validate(inventory)


def test_rejects_incompatible_image_evidence() -> None:
    inventory = _inventory()
    compatibility = inventory["image_compatibility"]
    assert isinstance(compatibility, dict)
    compatibility["status"] = "failed"

    with pytest.raises(ValueError, match="compatibility"):
        verify_inventory.validate(inventory)


def test_rejects_unverified_capacity_probe_cleanup() -> None:
    inventory = _inventory()
    probe = inventory["capacity_probe"]
    assert isinstance(probe, dict)
    probe["cleanup_state"] = "failed"

    with pytest.raises(ValueError, match="capacity probe"):
        verify_inventory.validate(inventory)
