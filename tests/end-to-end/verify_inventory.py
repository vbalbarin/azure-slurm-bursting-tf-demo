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
