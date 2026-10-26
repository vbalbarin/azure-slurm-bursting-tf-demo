from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import subprocess
from types import ModuleType

import pytest


ROOT = Path(__file__).parents[2]
STATE_TOOL = ROOT / "chef/bin/convergence_state.py"
IDEMPOTENCY = ROOT / "chef/test/integration/idempotency/verify.sh"


def _load_state_tool() -> ModuleType:
    specification = importlib.util.spec_from_file_location(
        "convergence_state", STATE_TOOL
    )
    assert specification is not None
    assert specification.loader is not None
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


def test_interrupted_atomic_write_preserves_last_valid_document(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    module = _load_state_tool()
    state_path = tmp_path / "state.json"
    original = {"state": "converged", "manifestDigest": "a" * 64}
    state_path.write_text(json.dumps(original), encoding="utf-8")

    def interrupt(_source: str, _destination: Path) -> None:
        raise OSError("injected interruption")

    monkeypatch.setattr(module.os, "replace", interrupt)
    with pytest.raises(OSError, match="injected interruption"):
        module.atomic_write(state_path, {"state": "failed"})

    assert json.loads(state_path.read_text(encoding="utf-8")) == original
    assert list(tmp_path.glob(".state.json.*")) == []


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8")
    path.chmod(0o755)


def _idempotency_environment(tmp_path: Path) -> dict[str, str]:
    cyclecloud_release = tmp_path / "cyclecloud"
    scheduler_release = tmp_path / "scheduler"
    cyclecloud_release.mkdir()
    scheduler_release.mkdir()
    (cyclecloud_release / "Policyfile.lock.json").write_text("cyclecloud")
    (scheduler_release / "Policyfile.lock.json").write_text("scheduler")
    cyclecloud = tmp_path / "cyclecloud.sh"
    scheduler = tmp_path / "scheduler.sh"
    _write_executable(cyclecloud, "#!/usr/bin/env bash\necho '0 resources updated'\n")
    _write_executable(scheduler, "#!/usr/bin/env bash\necho '0 resources updated'\n")
    return {
        **os.environ,
        "CYCLECLOUD_CONVERGE": str(cyclecloud),
        "SCHEDULER_CONVERGE": str(scheduler),
        "PROCESSOR_COMMAND": "printf '%s\\n' '{\"changed\": false}'",
        "CYCLECLOUD_STAGED_DIR": str(cyclecloud_release),
        "SCHEDULER_STAGED_DIR": str(scheduler_release),
    }


def test_idempotency_verifier_accepts_zero_updates_and_stable_releases(
    tmp_path: Path,
) -> None:
    result = subprocess.run(
        [str(IDEMPOTENCY)],
        cwd=ROOT,
        env=_idempotency_environment(tmp_path),
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_idempotency_verifier_rejects_staged_release_mutation(
    tmp_path: Path,
) -> None:
    environment = _idempotency_environment(tmp_path)
    cyclecloud = Path(environment["CYCLECLOUD_CONVERGE"])
    _write_executable(
        cyclecloud,
        """#!/usr/bin/env bash
count_file="${0}.count"
count="$(cat "$count_file" 2>/dev/null || echo 0)"
count=$((count + 1))
printf '%s' "$count" >"$count_file"
if (( count == 2 )); then
  printf 'changed' >>"$CYCLECLOUD_STAGED_DIR/Policyfile.lock.json"
fi
echo '0 resources updated'
""",
    )
    result = subprocess.run(
        [str(IDEMPOTENCY)],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "staged release changed" in result.stderr
