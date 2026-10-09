from __future__ import annotations

from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
SCRIPT = REPOSITORY_ROOT / "tests/end-to-end/export_preflight_env.sh"
EXAMPLE = REPOSITORY_ROOT / "terraform/environments/demo.tfvars.example"


def test_exports_non_secret_preflight_values() -> None:
    command = f"""
set -e
source {SCRIPT!s} {EXAMPLE!s}
printf '%s\\n' "$SOURCE_REGION|$BURST_REGION|$BURST_ZONE"
printf '%s\\n' "$CYCLECLOUD_VM_SIZE|$WINDOWS_VM_SIZE|$BURST_VM_SIZE"
printf '%s\\n' "$BURST_COMPUTE_URN"
printf '%s\\n' "$ALTERNATE_BURST_PLACEMENTS_JSON"
printf '%s\\n' "$TFVARS_FILE"
"""
    result = subprocess.run(
        ["bash", "-c", command],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert "eastus|southcentralus|1" in result.stdout
    assert "Standard_D4s_v6|Standard_D2s_v6|Standard_HB120rs_v3" in result.stdout
    assert (
        "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110" in result.stdout
    )
    assert '[{"region":"eastus2","zone":"1"}]' in result.stdout
    assert str(EXAMPLE) in result.stdout
    assert "certificate_secret" not in result.stdout
    assert "chef_policy" not in result.stdout


def test_rejects_execution_that_cannot_modify_parent_environment() -> None:
    result = subprocess.run(
        [str(SCRIPT), str(EXAMPLE)],
        cwd=REPOSITORY_ROOT,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 2
    assert "Source this script" in result.stderr
