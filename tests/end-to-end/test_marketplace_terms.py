from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess


REPOSITORY_ROOT = Path(__file__).parents[2]
SCRIPT = REPOSITORY_ROOT / "tests/end-to-end/marketplace_terms.sh"
EXAMPLE = REPOSITORY_ROOT / "terraform/environments/demo.tfvars.example"


def _write_fake_az(directory: Path) -> None:
    executable = directory / "az"
    executable.write_text(
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
accepted_file = Path(os.environ["FAKE_ACCEPTED_FILE"])

if args[:2] == ["account", "show"]:
    print(os.environ.get(
        "FAKE_SUBSCRIPTION_ID",
        "00000000-0000-0000-0000-000000000000",
    ))
elif args[:4] == ["vm", "image", "terms", "show"]:
    accepted = accepted_file.exists() or os.environ.get("FAKE_ACCEPTED") == "true"
    if "--query" in args:
        print(json.dumps({
            "urn": "https://example.invalid/terms",
            "accepted": accepted,
        }))
    else:
        print(json.dumps({
            "accepted": accepted,
            "licenseTextLink": "https://example.invalid/license",
            "privacyPolicyLink": "https://example.invalid/privacy",
            "marketplaceTermsLink": "https://example.invalid/terms",
            "retrieveDatetime": "2026-10-10T13:00:00Z",
        }))
elif args[:4] == ["vm", "image", "terms", "accept"]:
    accepted_file.write_text("accepted")
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
        "FAKE_ACCEPTED_FILE": str(tmp_path / "accepted"),
    }


def _run(
    tmp_path: Path, action: str, **overrides: str
) -> subprocess.CompletedProcess[str]:
    environment = _environment(tmp_path)
    environment.update(overrides)
    return subprocess.run(
        [str(SCRIPT), action, str(EXAMPLE)],
        cwd=REPOSITORY_ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )


def test_show_is_read_only(tmp_path: Path) -> None:
    result = _run(tmp_path, "show")

    assert result.returncode == 0, result.stderr
    evidence = json.loads(result.stdout)
    assert evidence["accepted"] is False
    assert evidence["subscription_id"] == (
        "00000000-0000-0000-0000-000000000000"
    )
    assert not (tmp_path / "accepted").exists()


def test_accept_requires_explicit_acknowledgement(tmp_path: Path) -> None:
    result = _run(tmp_path, "accept")

    assert result.returncode == 4
    assert "ACCEPT_MARKETPLACE_TERMS=yes" in result.stderr
    assert not (tmp_path / "accepted").exists()


def test_accepts_and_verifies_after_acknowledgement(tmp_path: Path) -> None:
    result = _run(tmp_path, "accept", ACCEPT_MARKETPLACE_TERMS="yes")

    assert result.returncode == 0, result.stderr
    assert (tmp_path / "accepted").exists()
    assert "accepted and verified" in result.stderr


def test_rejects_wrong_active_subscription(tmp_path: Path) -> None:
    result = _run(
        tmp_path,
        "show",
        FAKE_SUBSCRIPTION_ID="11111111-1111-1111-1111-111111111111",
    )

    assert result.returncode == 3
    assert "does not match" in result.stderr
