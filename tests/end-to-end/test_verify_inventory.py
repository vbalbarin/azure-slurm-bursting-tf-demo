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
                "2025-datacenter-azure-edition:latest"
            ),
        },
        "image_compatibility": {
            "status": "validated",
            "os_family": "almalinux",
            "os_major": "9",
        },
        "validation": {
            "plan_digest": "a" * 64,
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
