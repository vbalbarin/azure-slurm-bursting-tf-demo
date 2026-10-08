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
        "cluster_name",
        "private_hosts",
        "versions",
        "image_compatibility",
        "validation",
    }
    missing = required - inventory.keys()
    if missing:
        raise ValueError(f"Missing inventory fields: {sorted(missing)}")
    if inventory["source_region"] == inventory["burst_region"]:
        raise ValueError("Source and burst regions must differ")
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


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("inventory", type=Path)
    args = parser.parse_args()
    validate(json.loads(args.inventory.read_text()))


if __name__ == "__main__":
    main()
