from __future__ import annotations

import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import time
from unittest.mock import patch

import pytest


ROOT = Path(__file__).parents[2]
WORKFLOW = ROOT / "tests/end-to-end/converge_linux_roles.sh"
RETRIEVER = ROOT / "chef/bin/retrieve-key-vault-secret.py"
PUBLISHER = ROOT / "chef/bin/publish-hpc-user-receipt.sh"


def _load_retriever():
    spec = importlib.util.spec_from_file_location("retrieve_key_vault_secret", RETRIEVER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class _Response:
    def __init__(self, document: dict[str, str]):
        self._payload = json.dumps(document).encode()

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self) -> bytes:
        return self._payload


def test_key_vault_retrieval_uses_imds_client_identity_and_protected_output(
    tmp_path: Path,
) -> None:
    module = _load_retriever()
    output = tmp_path / "secret"
    requests = []

    def open_request(request, timeout):
        requests.append((request, timeout))
        if request.full_url.startswith("http://169.254.169.254/"):
            return _Response({"access_token": "protected-token"})
        return _Response({"value": "protected-value"})

    with patch.object(module.urllib.request, "urlopen", side_effect=open_request):
        assert (
            module.main(
                [
                    "--client-id",
                    "11111111-1111-1111-1111-111111111111",
                    "--vault-uri",
                    "https://demo.vault.azure.net/",
                    "--secret-name",
                    "cyclecloud-admin-password",
                    "--output",
                    str(output),
                ]
            )
            == 0
        )

    assert output.read_text() == "protected-value"
    assert stat.S_IMODE(output.stat().st_mode) == 0o600
    imds_request, key_vault_request = (item[0] for item in requests)
    assert "resource=https%3A%2F%2Fvault.azure.net" in imds_request.full_url
    assert "client_id=11111111-1111-1111-1111-111111111111" in imds_request.full_url
    assert imds_request.headers["Metadata"] == "true"
    assert key_vault_request.full_url == (
        "https://demo.vault.azure.net/secrets/"
        "cyclecloud-admin-password?api-version=7.4"
    )
    assert key_vault_request.headers["Authorization"] == "Bearer protected-token"


@pytest.mark.parametrize(
    "vault_uri",
    [
        "http://demo.vault.azure.net",
        "https://demo.example.com",
        "https://127.0.0.1",
        "https://demo.vault.azure.net/path",
    ],
)
def test_key_vault_retrieval_rejects_non_private_vault_contract(
    tmp_path: Path, vault_uri: str
) -> None:
    module = _load_retriever()
    with pytest.raises(SystemExit):
        module.main(
            [
                "--client-id",
                "11111111-1111-1111-1111-111111111111",
                "--vault-uri",
                vault_uri,
                "--secret-name",
                "cyclecloud-admin-password",
                "--output",
                str(tmp_path / "secret"),
            ]
        )


def test_secret_retrieval_has_no_azure_cli_and_wrapper_cleans_transients() -> None:
    retriever = RETRIEVER.read_text()
    wrapper = (ROOT / "chef/bin/converge-scheduler.sh").read_text()
    assert "az keyvault" not in retriever
    assert "subprocess" not in retriever
    assert "trap cleanup EXIT" in wrapper
    assert 'rm -f "$secret_file"' in wrapper
    assert "--policy-revision" in wrapper
    assert "--policy-lock-sha256" in wrapper


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def test_public_identity_receipt_is_canonical_and_value_free(tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    home = tmp_path / "shared/home/hpcuser01"
    ssh_dir = home / ".ssh"
    ssh_dir.mkdir(parents=True)
    public_key = (
        "ssh-ed25519 "
        "AAAAC3NzaC1lZDI1NTE5AAAAIB9J6MxuQ3Vf1P8dJ4Jcq9VIj7I+amcV2TYVqYqA2s7Z"
    )
    (ssh_dir / "id_ed25519.pub").write_text(public_key + " hpcuser01@scheduler\n")
    _write_executable(
        fake_bin / "getent",
        "#!/usr/bin/env bash\nprintf '%s\\n' 'hpcuser01:x:11200:11200::/shared/home/hpcuser01:/bin/bash'\n",
    )
    _write_executable(
        fake_bin / "ssh-keygen",
        "#!/usr/bin/env bash\nprintf '%s\\n' '256 SHA256:receiptFingerprint hpcuser01 (ED25519)'\n",
    )
    output = tmp_path / "receipt.json"
    source_revision = "a" * 40
    specification_digest = "b" * 64
    result = subprocess.run(
        [
            str(PUBLISHER),
            "--source-revision",
            source_revision,
            "--specification-digest",
            specification_digest,
            "--output",
            str(output),
        ],
        cwd=ROOT,
        env={
            **os.environ,
            "PATH": f"{fake_bin}:{os.environ['PATH']}",
            "HPC_PUBLIC_KEY_PATH": str(ssh_dir / "id_ed25519.pub"),
        },
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    receipt = json.loads(output.read_text())
    digest = receipt.pop("identityReceiptDigest")
    canonical = json.dumps(receipt, sort_keys=True, separators=(",", ":")).encode()
    import hashlib

    assert digest == hashlib.sha256(canonical).hexdigest()
    assert receipt == {
        "schemaVersion": 1,
        "name": "hpcuser01",
        "uid": 11200,
        "gid": 11200,
        "home": "/shared/home/hpcuser01",
        "publicKey": public_key,
        "publicKeyFingerprint": "SHA256:receiptFingerprint",
        "sourceRevision": source_revision,
        "specificationDigest": specification_digest,
    }
    assert "PRIVATE" not in output.read_text()


def _workflow_context(tmp_path: Path) -> Path:
    context = tmp_path / "run-context.env"
    context.write_text(
        "\n".join(
            [
                "AZURE_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000",
                "RESOURCE_GROUP=demo-rg",
                "CYCLECLOUD_VM_NAME=cyclecloud",
                "SCHEDULER_VM_NAME=scheduler",
                f"SOURCE_REVISION={'a' * 40}",
                f"CYCLECLOUD_MANIFEST_DIGEST={'b' * 64}",
                f"CYCLECLOUD_SPECIFICATION_DIGEST={'c' * 64}",
                f"SCHEDULER_MANIFEST_DIGEST={'d' * 64}",
                f"SCHEDULER_SPECIFICATION_DIGEST={'e' * 64}",
                f"EVIDENCE_DIR={tmp_path / 'evidence'}",
            ]
        )
        + "\n"
    )
    context.chmod(0o600)
    return context


def test_ui_attestation_validation_rejects_stale_or_overprivileged_records(
    tmp_path: Path,
) -> None:
    context = _workflow_context(tmp_path)
    receipt = tmp_path / "receipt.json"
    receipt_document = {
        "schemaVersion": 1,
        "name": "hpcuser01",
        "uid": 11200,
        "gid": 11200,
        "home": "/shared/home/hpcuser01",
        "publicKey": (
            "ssh-ed25519 "
            "AAAAC3NzaC1lZDI1NTE5AAAAIB9J6MxuQ3Vf1P8dJ4Jcq9VIj7I+amcV2TYVqYqA2s7Z"
        ),
        "publicKeyFingerprint": "SHA256:current",
        "sourceRevision": "a" * 40,
        "specificationDigest": "e" * 64,
    }
    import hashlib

    receipt_document["identityReceiptDigest"] = hashlib.sha256(
        json.dumps(receipt_document, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    receipt.write_text(json.dumps(receipt_document))
    attestation = tmp_path / "attestation.json"
    attestation.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "operator": "reviewer@example.invalid",
                "recordedAt": "2026-10-26T12:00:00Z",
                "userName": "hpcuser01",
                "superuser": True,
                "nodeAccessEnabled": True,
                "uid": 11200,
                "publicKeyFingerprint": "SHA256:stale",
                "sourceRevision": "a" * 40,
                "specificationDigest": "e" * 64,
                "identityReceiptDigest": receipt_document["identityReceiptDigest"],
                "clusterName": "cross-region-demo",
                "clusterPermission": "administrator",
                "applicationPasswordDisposition": "retained",
                "result": "accepted",
            }
        )
    )
    result = subprocess.run(
        [
            str(WORKFLOW),
            "--run-context",
            str(context),
            "--operation",
            "validate-ui-attestation",
            "--identity-receipt",
            str(receipt),
            "--ui-attestation",
            str(attestation),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode != 0
    assert "attestation" in result.stderr.lower()


def test_ui_attestation_accepts_only_receipt_bound_supported_outcome(
    tmp_path: Path,
) -> None:
    context = _workflow_context(tmp_path)
    receipt_document = {
        "schemaVersion": 1,
        "name": "hpcuser01",
        "uid": 11200,
        "gid": 11200,
        "home": "/shared/home/hpcuser01",
        "publicKey": (
            "ssh-ed25519 "
            "AAAAC3NzaC1lZDI1NTE5AAAAIB9J6MxuQ3Vf1P8dJ4Jcq9VIj7I+amcV2TYVqYqA2s7Z"
        ),
        "publicKeyFingerprint": "SHA256:current",
        "sourceRevision": "a" * 40,
        "specificationDigest": "e" * 64,
    }
    import hashlib

    receipt_document["identityReceiptDigest"] = hashlib.sha256(
        json.dumps(receipt_document, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    receipt = tmp_path / "receipt.json"
    receipt.write_text(json.dumps(receipt_document))
    attestation = tmp_path / "attestation.json"
    attestation.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "operator": "reviewer@example.invalid",
                "recordedAt": "2026-10-26T12:00:00Z",
                "userName": "hpcuser01",
                "superuser": False,
                "nodeAccessEnabled": True,
                "uid": 11200,
                "publicKeyFingerprint": "SHA256:current",
                "sourceRevision": "a" * 40,
                "specificationDigest": "e" * 64,
                "identityReceiptDigest": receipt_document["identityReceiptDigest"],
                "clusterName": "cross-region-demo",
                "clusterPermission": "node-user",
                "applicationPasswordDisposition": "force-reset-discarded",
                "result": "accepted",
            }
        )
    )
    result = subprocess.run(
        [
            str(WORKFLOW),
            "--run-context",
            str(context),
            "--operation",
            "validate-ui-attestation",
            "--identity-receipt",
            str(receipt),
            "--ui-attestation",
            str(attestation),
        ],
        cwd=ROOT,
        check=False,
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stderr


def test_workflow_has_bounded_state_inspection_and_no_user_api() -> None:
    content = WORKFLOW.read_text()
    assert "timeout 55" in content
    assert "state.json" in content
    assert "run-command invoke" in content
    assert "/api/users" not in content
    assert "/opt/cycle_server/config/data" not in content
    assert "cyclecloud account" not in content


def test_workflow_requires_approved_side_by_side_update_and_rollback() -> None:
    content = WORKFLOW.read_text()
    assert "initial|retry|update|verify-idempotency" in content
    assert "--update-role" in content
    assert "--update-payload-dir" in content
    assert "approved update payload validation failed" in content
    assert "--state update_authorized" in content
    assert "update-previous-release" in content
    assert "update-previous-state.json" in content
    assert "SLURM_DEMO_PREVIOUS_RELEASE" in content
    assert "SLURM_DEMO_PREVIOUS_STATE" in content


def test_remote_state_inspection_validates_both_roles_within_bound(
    tmp_path: Path,
) -> None:
    context = _workflow_context(tmp_path)
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_executable(
        fake_bin / "az",
        """#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
vm = args[args.index("--name") + 1]
role = "cyclecloud" if vm == "cyclecloud" else "scheduler"
state = {
    "schemaVersion": 1,
    "role": role,
    "state": "converged" if role == "cyclecloud" else "waiting_dependencies",
    "sourceRevision": "a" * 40,
    "manifestDigest": ("b" if role == "cyclecloud" else "d") * 64,
    "specificationDigest": ("c" if role == "cyclecloud" else "e") * 64,
    "attempt": 1 if role == "cyclecloud" else 0,
    "updatedAt": "2026-10-26T12:00:00Z",
    "detailCode": "complete" if role == "cyclecloud" else "staged",
}
print(json.dumps({"value": [{"message": json.dumps(state)}]}))
""",
    )
    started = time.monotonic()
    result = subprocess.run(
        [
            str(WORKFLOW),
            "--run-context",
            str(context),
            "--operation",
            "inspect",
        ],
        cwd=ROOT,
        env={**os.environ, "PATH": f"{fake_bin}:{os.environ['PATH']}"},
        check=False,
        capture_output=True,
        text=True,
        timeout=5,
    )
    elapsed = time.monotonic() - started
    assert result.returncode == 0, result.stderr
    assert elapsed < 5
    evidence = tmp_path / "evidence"
    assert json.loads((evidence / "cyclecloud-state.json").read_text())["role"] == (
        "cyclecloud"
    )
    assert json.loads((evidence / "scheduler-state.json").read_text())["state"] == (
        "waiting_dependencies"
    )
