from __future__ import annotations

import argparse
import json
from pathlib import Path
import re


SECRET_FIELD = re.compile(r"(password|private[_-]?key|secret[_-]?value)", re.IGNORECASE)


def validate(inventory: dict[str, object]) -> None:
    required = {
        "environment_name",
        "source_region",
        "burst_region",
        "burst_zone",
        "planned_role_counts",
        "cluster_name",
        "private_hosts",
        "versions",
        "image_compatibility",
        "capacity_assessment",
        "capacity_probe",
        "validation",
    }
    missing = required - inventory.keys()
    if missing:
        raise ValueError(f"Missing inventory fields: {sorted(missing)}")
    if inventory["source_region"] == inventory["burst_region"]:
        raise ValueError("Source and burst regions must differ")
    if inventory["burst_zone"] not in {"1", "2", "3"}:
        raise ValueError("Burst zone must be 1, 2, or 3")
    if inventory["planned_role_counts"] != {
        "cyclecloud": 1,
        "scheduler": 1,
        "windows_admin": 1,
        "burst_compute": 1,
    }:
        raise ValueError("Inventory planned role counts are invalid")
    serialized = json.dumps(inventory, sort_keys=True)
    if SECRET_FIELD.search(serialized):
        raise ValueError("Inventory contains a prohibited secret-shaped field")
    private_hosts = inventory["private_hosts"]
    if not isinstance(private_hosts, dict) or set(private_hosts) != {
        "cyclecloud",
        "scheduler",
        "windows_admin",
    }:
        raise ValueError("Inventory must contain exactly the three persistent hosts")
    versions = inventory["versions"]
    if not isinstance(versions, dict):
        raise ValueError("Inventory versions must be an object")
    required_images = {"scheduler_image", "burst_compute_image", "windows_image"}
    if not required_images.issubset(versions):
        raise ValueError("Inventory must contain every role-specific image")
    scheduler_image = str(versions["scheduler_image"])
    burst_compute_image = str(versions["burst_compute_image"])
    scheduler_match = re.fullmatch(
        r"almalinux:almalinux-x86_64:(\d+)-gen[12]:\d+\.\d+\.\d+",
        scheduler_image,
    )
    burst_match = re.fullmatch(
        r"almalinux:almalinux-hpc:(\d+)-hpc-gen[12]:\d+\.\d+\.\d+",
        burst_compute_image,
    )
    if not scheduler_match or not burst_match:
        raise ValueError("Inventory contains an invalid role-specific image")
    if scheduler_image == burst_compute_image:
        raise ValueError("Scheduler and burst compute images must be independently pinned")
    if scheduler_match.group(1) != burst_match.group(1):
        raise ValueError("Scheduler and burst compute operating-system majors differ")
    compatibility = inventory["image_compatibility"]
    if (
        not isinstance(compatibility, dict)
        or compatibility.get("status") != "validated"
        or compatibility.get("os_family") != "almalinux"
        or str(compatibility.get("os_major")) != scheduler_match.group(1)
    ):
        raise ValueError("Inventory image compatibility evidence is invalid")
    validation = inventory["validation"]
    if not isinstance(validation, dict) or not re.fullmatch(
        r"[a-f0-9]{64}", str(validation.get("plan_digest", ""))
    ):
        raise ValueError("Inventory must contain the reviewed saved-plan digest")
    for digest_name in ("preflight_digest", "capacity_probe_digest"):
        if not re.fullmatch(r"[a-f0-9]{64}", str(validation.get(digest_name, ""))):
            raise ValueError(f"Inventory must contain {digest_name}")
    assessment = inventory["capacity_assessment"]
    if not isinstance(assessment, dict) or assessment.get("status") != "validated":
        raise ValueError("Inventory capacity assessment is invalid")
    probe = inventory["capacity_probe"]
    if (
        not isinstance(probe, dict)
        or probe.get("allocation_state") != "allocated"
        or probe.get("cleanup_state") != "verified"
        or probe.get("guarantee") != "point_in_time_only"
        or probe.get("region") != inventory["burst_region"]
        or probe.get("zone") != inventory["burst_zone"]
        or probe.get("image_urn") != burst_compute_image
    ):
        raise ValueError("Inventory capacity probe evidence is invalid")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    validate(json.loads(args.inventory.read_text()))


if __name__ == "__main__":
    main()
