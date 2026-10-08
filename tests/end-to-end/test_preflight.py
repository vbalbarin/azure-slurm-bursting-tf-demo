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
import os
import sys

args = sys.argv[1:]
query = args[args.index("--query") + 1] if "--query" in args else ""

if args[:2] == ["account", "show"]:
    print("00000000-0000-0000-0000-000000000000")
elif args[:2] == ["account", "list-locations"]:
    print("eastus")
    print("southcentralus")
elif args[:2] == ["vm", "list-skus"]:
    size = args[args.index("--size") + 1]
    role = "BURST" if size == "Standard_HB120rs_v3" else "SCHEDULER"
    if "restrictions" in query:
        pass
    elif "length" in query:
        print("1")
    elif "HyperVGenerations" in query:
        print(os.environ.get(f"FAKE_{role}_SIZE_HYPERV", "V2"))
    elif "CpuArchitectureType" in query:
        print(os.environ.get(f"FAKE_{role}_SIZE_ARCH", "x64"))
elif args[:3] == ["vm", "image", "show"]:
    urn = ":".join(
        args[args.index(option) + 1]
        for option in ("--publisher", "--offer", "--sku", "--version")
    )
    if urn == os.environ.get("FAKE_MISSING_URN"):
        sys.exit(3)
    role = "BURST" if ":almalinux-hpc:" in urn else "SCHEDULER"
    if "hyperVGeneration" in query:
        print(os.environ.get(f"FAKE_{role}_IMAGE_HYPERV", "V2"))
    elif "architecture" in query:
        print(os.environ.get(f"FAKE_{role}_IMAGE_ARCH", "x64"))
elif args[:3] == ["vm", "image", "terms"]:
    print("true")
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
        "CYCLECLOUD_VM_SIZE": "Standard_D4s_v6",
        "SCHEDULER_VM_SIZE": "Standard_D4s_v6",
        "WINDOWS_VM_SIZE": "Standard_D2s_v5",
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
            "2025-datacenter-azure-edition:latest"
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


def test_rejects_unavailable_burst_image(tmp_path: Path) -> None:
    missing = "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
    result = _run(tmp_path, FAKE_MISSING_URN=missing)

    assert result.returncode != 0


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
