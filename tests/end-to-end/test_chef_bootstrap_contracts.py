from __future__ import annotations

import json
import hashlib
import fcntl
import os
from pathlib import Path
import shutil
import subprocess

import pytest
from jsonschema import Draft202012Validator, FormatChecker


ROOT = Path(__file__).resolve().parents[2]
CONTRACTS = ROOT / "specs" / "005-automated-chef-bootstrap" / "contracts"
BUILDER = ROOT / "tests" / "end-to-end" / "build_chef_policy_bundles.sh"
STATE_TOOL = ROOT / "chef" / "bin" / "convergence_state.py"
BOOTSTRAP = ROOT / "chef" / "bootstrap" / "linux.sh"
CYCLECLOUD_WRAPPER = ROOT / "chef" / "bin" / "converge-cyclecloud.sh"
SCHEDULER_WRAPPER = ROOT / "chef" / "bin" / "converge-scheduler.sh"


def _validator(name: str) -> Draft202012Validator:
    schema = json.loads((CONTRACTS / name).read_text(encoding="utf-8"))
    Draft202012Validator.check_schema(schema)
    return Draft202012Validator(schema, format_checker=FormatChecker())


def _attestation() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "operator": "operator@example.invalid",
        "recordedAt": "2026-10-26T12:00:00Z",
        "userName": "hpcuser01",
        "superuser": False,
        "nodeAccessEnabled": True,
        "uid": 11200,
        "publicKeyFingerprint": "SHA256:abcdefghijklmnop",
        "sourceRevision": "a" * 40,
        "specificationDigest": "b" * 64,
        "identityReceiptDigest": "c" * 64,
        "clusterName": "cross-region-demo",
        "clusterPermission": "node-user",
        "applicationPasswordDisposition": "force-reset-discarded",
        "result": "accepted",
    }


def test_all_json_contracts_are_valid_draft_2020_12_schemas() -> None:
    schemas = sorted(CONTRACTS.glob("*.schema.json"))
    assert schemas
    for schema in schemas:
        Draft202012Validator.check_schema(json.loads(schema.read_text(encoding="utf-8")))


def test_cyclecloud_user_attestation_accepts_the_governed_shape() -> None:
    assert list(_validator("cyclecloud-user-attestation.schema.json").iter_errors(_attestation())) == []


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("userName", "other"),
        ("superuser", True),
        ("nodeAccessEnabled", False),
        ("uid", 11201),
        ("clusterName", "other"),
        ("clusterPermission", "administrator"),
        ("applicationPasswordDisposition", "stored"),
        ("sourceRevision", "main"),
        ("specificationDigest", "bad"),
        ("identityReceiptDigest", "bad"),
    ],
)
def test_cyclecloud_user_attestation_rejects_unsafe_or_unbound_values(
    field: str, value: object
) -> None:
    document = _attestation()
    document[field] = value
    assert list(_validator("cyclecloud-user-attestation.schema.json").iter_errors(document))


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def test_policy_bundle_build_is_deterministic_and_lock_bound(tmp_path: Path) -> None:
    outputs = [tmp_path / "first", tmp_path / "second"]
    for output in outputs:
        subprocess.run(
            [
                str(BUILDER),
                "--source-revision",
                "a" * 40,
                "--output-dir",
                str(output),
            ],
            cwd=ROOT,
            check=True,
        )

    for role in ("cyclecloud", "scheduler"):
        archive = f"{role}.tgz"
        manifest_name = f"{role}.manifest.json"
        assert _sha256(outputs[0] / archive) == _sha256(outputs[1] / archive)
        assert (outputs[0] / manifest_name).read_bytes() == (
            outputs[1] / manifest_name
        ).read_bytes()

        manifest = json.loads((outputs[0] / manifest_name).read_text(encoding="utf-8"))
        assert manifest["sourceRevision"] == "a" * 40
        assert len(manifest["policyRevision"]) == 64
        assert len(manifest["policyLockSha256"]) == 64
        assert len(manifest["manifestDigest"]) == 64
        assert {item["kind"] for item in manifest["artifacts"]} >= {
            "policy",
            "policy-lock",
            "package",
        }
        assert os.path.getsize(outputs[0] / archive) * 4 / 3 <= 60_000


def _run_state(
    state_dir: Path, *arguments: str, check: bool = True
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [
            "python3",
            str(STATE_TOOL),
            "--state-dir",
            str(state_dir),
            *arguments,
        ],
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=check,
    )


def test_state_machine_allows_one_identical_retry_then_requires_replacement(
    tmp_path: Path,
) -> None:
    common = (
        "--role",
        "scheduler",
        "--source-revision",
        "a" * 40,
        "--manifest-digest",
        "b" * 64,
        "--specification-digest",
        "c" * 64,
    )
    _run_state(tmp_path, "transition", *common, "--state", "converging", "--attempt", "1")
    _run_state(
        tmp_path,
        "transition",
        *common,
        "--state",
        "failed_retryable",
        "--attempt",
        "1",
        "--detail-code",
        "chef_failed",
    )
    _run_state(tmp_path, "transition", *common, "--state", "converging", "--attempt", "2")
    _run_state(
        tmp_path,
        "transition",
        *common,
        "--state",
        "replacement_required",
        "--attempt",
        "2",
        "--detail-code",
        "chef_failed",
    )

    blocked = _run_state(
        tmp_path,
        "transition",
        *common,
        "--state",
        "converging",
        "--attempt",
        "2",
        check=False,
    )
    assert blocked.returncode != 0
    state = json.loads((tmp_path / "scheduler" / "state.json").read_text())
    assert state["state"] == "replacement_required"


def test_state_machine_rejects_changed_retry_digests(tmp_path: Path) -> None:
    common = (
        "--role",
        "cyclecloud",
        "--source-revision",
        "a" * 40,
        "--manifest-digest",
        "b" * 64,
        "--specification-digest",
        "c" * 64,
    )
    _run_state(
        tmp_path,
        "transition",
        *common,
        "--state",
        "failed_retryable",
        "--attempt",
        "1",
    )
    changed = _run_state(
        tmp_path,
        "transition",
        "--role",
        "cyclecloud",
        "--source-revision",
        "a" * 40,
        "--manifest-digest",
        "d" * 64,
        "--specification-digest",
        "c" * 64,
        "--state",
        "converging",
        "--attempt",
        "2",
        check=False,
    )
    assert changed.returncode != 0


def test_common_bootstrap_is_lock_bound_and_atomically_selects_releases() -> None:
    script = BOOTSTRAP.read_text(encoding="utf-8")
    assert "18.11.11" in script
    assert "d68c339bc85ded67b793de4e20f35886c5fbd9b5a9e95dabbe5ede6211b01365" in script
    assert "CHEF_MANIFEST_PATH" in script
    assert "CHEF_NODE_SPECIFICATION_PATH" in script
    assert "CHEF_POLICY_ARCHIVE_PATH" in script
    assert "policyLockSha256" in script
    assert "release_root=/opt/slurm-demo/releases" in script
    assert "os.replace" in script
    assert "tar --extract" in script


def test_common_bootstrap_validates_before_extracting() -> None:
    script = BOOTSTRAP.read_text(encoding="utf-8")
    validation = script.index("manifestDigest")
    extraction = script.index("tar --extract")
    assert validation < extraction


def test_cyclecloud_wrapper_binds_state_and_evidence_to_verified_inputs() -> None:
    script = CYCLECLOUD_WRAPPER.read_text(encoding="utf-8")
    assert "flock -n" in script
    assert "manifestDigest" in script
    assert "specificationDigest" in script
    assert "policyRevision" in script
    assert "policyLockSha256" in script
    assert "--policy-revision" in script
    assert "--policy-lock-sha256" in script
    assert "failed_retryable" in script
    assert "replacement_required" in script
    assert "cleanup-verified" in script
    assert "/opt/slurm-demo/current" in script


def test_convergence_wrappers_use_supported_chef_policy_configuration() -> None:
    for path in (CYCLECLOUD_WRAPPER, SCHEDULER_WRAPPER):
        script = path.read_text(encoding="utf-8")
        assert "--policy-name" not in script
        assert "--policy-group" not in script
        assert "CHEF_LICENSE=accept-no-persist chef-client" in script
        assert '--config "$chef_config"' in script
        assert '--override-runlist "$chef_run_list"' in script
        assert "cookbook_path [" in script


def _cyclecloud_wrapper_fixture(
    tmp_path: Path, chef_exit: int = 0
) -> tuple[dict[str, str], Path]:
    release = tmp_path / "current"
    state_root = tmp_path / "state"
    runtime_root = tmp_path / "run"
    (release / "chef/bin").mkdir(parents=True)
    (release / "chef/policyfiles").mkdir(parents=True)
    shutil.copy2(STATE_TOOL, release / "chef/bin/convergence_state.py")
    policy_revision = "d" * 64
    lock = {
        "revision_id": policy_revision,
        "run_list": ["recipe[cyclecloud_node::default]"],
    }
    lock_path = release / "chef/policyfiles/cyclecloud.lock.json"
    lock_path.write_text(json.dumps(lock), encoding="utf-8")
    lock_digest = _sha256(lock_path)
    specification = {"role": "cyclecloud", "sourceRevision": "a" * 40}
    specification["specificationDigest"] = hashlib.sha256(
        json.dumps(
            specification, sort_keys=True, separators=(",", ":")
        ).encode()
    ).hexdigest()
    (release / "node-specification.json").write_text(
        json.dumps(specification), encoding="utf-8"
    )
    manifest = {
        "role": "cyclecloud",
        "sourceRevision": "a" * 40,
        "policyName": "cyclecloud",
        "policyRevision": policy_revision,
        "policyLockSha256": lock_digest,
        "artifacts": [
            {
                "name": "azure-slurm-pkg-4.0.11.tar.gz",
                "kind": "project",
                "version": "4.0.11",
                "uri": "https://github.com/Azure/cyclecloud-slurm/releases/download/4.0.11/azure-slurm-pkg-4.0.11.tar.gz",
                "sha256": "f85a1d016eca3786eb9845fcbffcefaf674bfcd4b59738597e90877047a23e36",
                "sizeBytes": 1,
            }
        ],
    }
    manifest["manifestDigest"] = hashlib.sha256(
        json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()
    (release / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    chef = fake_bin / "chef-client"
    chef.write_text(
        "#!/usr/bin/env bash\n"
        + (
            "echo 'Chef Infra Client finished, 2/9 resources updated in 1 seconds'\n"
            if chef_exit == 0
            else "echo 'protected-test-value' >&2\n"
        )
        + f"exit {chef_exit}\n",
        encoding="utf-8",
    )
    chef.chmod(0o755)
    environment = {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "SLURM_DEMO_CURRENT": str(release),
        "SLURM_DEMO_STATE_ROOT": str(state_root),
        "SLURM_DEMO_RUNTIME_ROOT": str(runtime_root),
    }
    return environment, state_root


def test_cyclecloud_wrapper_records_lock_bound_converged_evidence(
    tmp_path: Path,
) -> None:
    environment, state_root = _cyclecloud_wrapper_fixture(tmp_path)
    result = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    evidence = json.loads(
        (state_root / "cyclecloud/evidence/attempt-1-converged.json").read_text()
    )
    assert evidence["policyRevision"] == "d" * 64
    assert evidence["policyLockSha256"] == _sha256(
        Path(environment["SLURM_DEMO_CURRENT"])
        / "chef/policyfiles/cyclecloud.lock.json"
    )
    assert evidence["updatedResources"] == 2
    assert evidence["cleanupVerified"] is True


def test_cyclecloud_wrapper_allows_one_retry_then_requires_replacement(
    tmp_path: Path,
) -> None:
    environment, state_root = _cyclecloud_wrapper_fixture(tmp_path, chef_exit=1)
    first = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    second = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert first.returncode == 1
    assert second.returncode == 1
    assert "protected-test-value" not in first.stderr + second.stderr
    state = json.loads((state_root / "cyclecloud/state.json").read_text())
    assert state["attempt"] == 2
    assert state["state"] == "replacement_required"


def test_cyclecloud_wrapper_rejects_lock_contention(tmp_path: Path) -> None:
    environment, state_root = _cyclecloud_wrapper_fixture(tmp_path)
    role_state = state_root / "cyclecloud"
    role_state.mkdir(parents=True)
    with (role_state / "wrapper.lock").open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = subprocess.run(
            [str(CYCLECLOUD_WRAPPER)],
            cwd=ROOT,
            env=environment,
            text=True,
            capture_output=True,
            check=False,
        )
    assert result.returncode == 75


def test_cyclecloud_update_failure_restores_prior_release_and_state(
    tmp_path: Path,
) -> None:
    environment, state_root = _cyclecloud_wrapper_fixture(tmp_path, chef_exit=1)
    current = Path(environment["SLURM_DEMO_CURRENT"])
    releases = tmp_path / "releases"
    releases.mkdir()
    candidate = releases / ("b" * 64)
    current.rename(candidate)
    current.symlink_to(candidate, target_is_directory=True)
    previous = releases / ("a" * 64)
    previous.mkdir()

    manifest = json.loads((candidate / "manifest.json").read_text())
    specification = json.loads((candidate / "node-specification.json").read_text())
    _run_state(
        state_root,
        "transition",
        "--role",
        "cyclecloud",
        "--source-revision",
        manifest["sourceRevision"],
        "--manifest-digest",
        manifest["manifestDigest"],
        "--specification-digest",
        specification["specificationDigest"],
        "--state",
        "update_authorized",
        "--attempt",
        "0",
        "--detail-code",
        "approved_update",
    )
    previous_state = state_root / "cyclecloud/update-previous-state.json"
    previous_document = {
        "schemaVersion": 1,
        "role": "cyclecloud",
        "state": "converged",
        "sourceRevision": "f" * 40,
        "manifestDigest": "e" * 64,
        "specificationDigest": "d" * 64,
        "attempt": 1,
        "updatedAt": "2026-10-26T12:00:00Z",
        "detailCode": "complete",
    }
    previous_state.write_text(json.dumps(previous_document), encoding="utf-8")
    environment.update(
        {
            "CONVERGENCE_OPERATION": "update",
            "SLURM_DEMO_PREVIOUS_RELEASE": str(previous),
            "SLURM_DEMO_PREVIOUS_STATE": str(previous_state),
        }
    )

    result = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert result.returncode == 1
    assert current.resolve() == previous.resolve()
    assert json.loads((state_root / "cyclecloud/state.json").read_text()) == (
        previous_document
    )
    update_evidence = (
        state_root / "cyclecloud/evidence/attempt-1-update_failed.json"
    )
    assert update_evidence.is_file()
    assert json.loads(update_evidence.read_text())["failureStage"] == "chef"


def test_cyclecloud_idempotency_fails_closed_on_nonzero_updates(
    tmp_path: Path,
) -> None:
    environment, state_root = _cyclecloud_wrapper_fixture(tmp_path)
    first = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )
    assert first.returncode == 0
    environment["CONVERGENCE_OPERATION"] = "verify-idempotency"

    second = subprocess.run(
        [str(CYCLECLOUD_WRAPPER)],
        cwd=ROOT,
        env=environment,
        text=True,
        capture_output=True,
        check=False,
    )

    assert second.returncode == 1
    assert "updated resources" in second.stderr
    evidence = (
        state_root / "cyclecloud/evidence/attempt-1-idempotency_failed.json"
    )
    assert json.loads(evidence.read_text())["updatedResources"] == 2


def test_convergence_evidence_is_schema_valid_and_immutable(tmp_path: Path) -> None:
    arguments = (
        "record-evidence",
        "--role",
        "cyclecloud",
        "--source-revision",
        "a" * 40,
        "--manifest-digest",
        "b" * 64,
        "--specification-digest",
        "c" * 64,
        "--policy-revision",
        "d" * 64,
        "--policy-lock-sha256",
        "e" * 64,
        "--attempt",
        "1",
        "--result",
        "succeeded",
        "--state",
        "converged",
        "--updated-resources",
        "4",
        "--started-at",
        "2026-10-26T12:00:00Z",
        "--finished-at",
        "2026-10-26T12:01:00Z",
        "--cleanup-verified",
        "--dependency-receipt",
        f"cyclecloud_identity={'f' * 64}",
        "--hpc-user-uid",
        "11200",
        "--hpc-user-gid",
        "11200",
        "--hpc-user-key-fingerprint",
        "SHA256:abcdefghijklmnop",
    )
    _run_state(tmp_path, *arguments)
    evidence_path = (
        tmp_path / "cyclecloud" / "evidence" / "attempt-1-converged.json"
    )
    evidence = json.loads(evidence_path.read_text(encoding="utf-8"))
    assert (
        list(
            _validator("convergence-evidence.schema.json").iter_errors(evidence)
        )
        == []
    )

    changed = list(arguments)
    changed[changed.index("4")] = "5"
    result = _run_state(tmp_path, *changed, check=False)
    assert result.returncode != 0
    assert json.loads(evidence_path.read_text(encoding="utf-8")) == evidence


def test_convergence_evidence_rejects_partial_hpc_identity(tmp_path: Path) -> None:
    result = _run_state(
        tmp_path,
        "record-evidence",
        "--role",
        "scheduler",
        "--source-revision",
        "a" * 40,
        "--manifest-digest",
        "b" * 64,
        "--specification-digest",
        "c" * 64,
        "--policy-revision",
        "d" * 64,
        "--policy-lock-sha256",
        "e" * 64,
        "--attempt",
        "1",
        "--result",
        "succeeded",
        "--state",
        "converged",
        "--updated-resources",
        "0",
        "--started-at",
        "2026-10-26T12:00:00Z",
        "--finished-at",
        "2026-10-26T12:01:00Z",
        "--hpc-user-uid",
        "11200",
        check=False,
    )
    assert result.returncode != 0
    assert "all HPC user evidence fields" in result.stderr
