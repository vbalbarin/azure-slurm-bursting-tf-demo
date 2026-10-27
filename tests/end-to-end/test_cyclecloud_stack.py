from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess

import pytest


ROOT = Path(__file__).parents[2]
STACK_SCRIPT = ROOT / "tests/end-to-end/cyclecloud_stack.sh"
SECRET_SCRIPT = ROOT / "tests/end-to-end/store_admin_secrets.sh"
BOOTSTRAP_SECRET_SCRIPT = (
    ROOT / "tests/end-to-end/generate_cyclecloud_bootstrap_secrets.sh"
)
FIRST_RUN = ROOT / "infra/cyclecloud/bootstrap.sh"
BICEP_TEMPLATE = ROOT / "infra/cyclecloud/main.bicep"
CONVERGENCE_WRAPPER = ROOT / "chef/bin/converge-cyclecloud.sh"


def _write_executable(path: Path, content: str) -> None:
    path.write_text(content)
    path.chmod(0o755)


def test_cyclecloud_first_run_stages_verified_payload_before_convergence() -> None:
    script = FIRST_RUN.read_text(encoding="utf-8")
    assert "CYCLECLOUD_CHEF_PAYLOAD_B64" in script
    assert "CYCLECLOUD_CHEF_PAYLOAD_SHA256" in script
    assert "CYCLECLOUD_CHEF_MANIFEST_B64" in script
    assert "CYCLECLOUD_CHEF_SPECIFICATION_B64" in script
    assert "CYCLECLOUD_CHEF_POLICY_LOCK_B64" in script
    assert script.index('touch "$state_dir/complete"') < script.index(
        "CHEF_POLICY_NAME=cyclecloud"
    )
    assert script.index("sha256sum") < script.index("chef/bootstrap/linux.sh")
    assert script.index("chef/bootstrap/linux.sh") < script.index(
        "chef/bin/converge-cyclecloud.sh"
    )


def test_cyclecloud_first_run_cleans_protected_material_and_is_reboot_safe() -> None:
    script = FIRST_RUN.read_text(encoding="utf-8")
    assert 'rm -rf "$secret_dir"' in script
    license_download = script.index(
        'download_secret chef-license-id "$secret_dir/chef-license-id"'
    )
    chef_bootstrap = script.index('"$chef_input_dir/bootstrap-linux.sh"')
    assert 'rm -rf "$secret_dir"' not in script[license_download:chef_bootstrap]
    assert 'if [[ -f "$state_dir/converged" ]]' in script
    assert "exec /opt/slurm-demo/current/chef/bin/converge-cyclecloud.sh" not in script


def test_cyclecloud_first_run_waits_for_system_identity_authorization() -> None:
    script = FIRST_RUN.read_text(encoding="utf-8")
    assert "az login --identity --allow-no-subscriptions" in script
    assert "--client-id" not in script
    assert "SECONDS + 1800" in script
    assert "generate-sas" in script
    assert "--as-user" in script
    assert "managementAccessVerified: true" in script
    assert "userDelegationVerified: true" in script
    assert "secretReadVerified: true" in script
    assert "AzureRMClientId" not in script
    assert "LockerIdentity" in script


def test_cyclecloud_bicep_declares_payload_contract_without_more_resources() -> None:
    template = BICEP_TEMPLATE.read_text(encoding="utf-8")
    for parameter in (
        "chefPayloadBase64",
        "chefManifestBase64",
        "chefNodeSpecificationBase64",
        "chefPolicyLockBase64",
        "chefPayloadSha256",
        "chefManifestSha256",
        "chefNodeSpecificationSha256",
        "chefPolicyLockSha256",
    ):
        assert f"param {parameter} string" in template
    assert "@maxLength(80000)" in template
    assert "@maxLength(87380)" in template
    assert "@maxValue(60000)" in template
    assert sum(line.startswith("resource ") for line in template.splitlines()) == 1
    assert "type: 'SystemAssigned'" in template
    assert "userAssignedIdentities" not in template
    assert "userAssignedIdentityResourceId" not in template
    assert "systemAssignedPrincipalId" in template


def test_cyclecloud_stack_passes_terraform_payload_contract_to_bicep() -> None:
    script = STACK_SCRIPT.read_text(encoding="utf-8")
    for field in (
        "chef_payload_base64",
        "chef_manifest_base64",
        "chef_node_specification_base64",
        "chef_policy_lock_base64",
        "chef_payload_sha256",
        "chef_manifest_sha256",
        "chef_node_specification_sha256",
        "chef_policy_lock_sha256",
        "chef_decoded_size_bytes",
    ):
        assert f".{field}" in script
    for parameter in (
        "chefPayloadBase64",
        "chefManifestBase64",
        "chefNodeSpecificationBase64",
        "chefPolicyLockBase64",
        "chefPayloadSha256",
        "chefManifestSha256",
        "chefNodeSpecificationSha256",
        "chefPolicyLockSha256",
        "chefDecodedSizeBytes",
    ):
        assert f"{parameter}: {{value:" in script
    assert "userAssignedIdentityResourceId" not in script
    assert "rbac-apply" in script
    assert "rbac-remove-apply" in script
    assert "identity-receipt" in script


def test_cyclecloud_stack_governs_post_create_and_pre_delete_rbac() -> None:
    script = STACK_SCRIPT.read_text(encoding="utf-8")
    assert "verify_plan_approval" in script
    assert "Approved CycleCloud RBAC plan digest does not match" in script
    assert "expected_phase=post-create-rbac" in script
    assert "expected_phase=foundation" in script
    assert "entra_p1_receipt_digest" in script
    assert 'terraform -chdir=terraform apply' in script
    assert '.post_create_rbac_enabled == false' in script
    assert "az role assignment list" in script
    assert "role assignments still exist" in script
    assert "cyclecloud-identity-rbac.schema.json" in script


def test_cyclecloud_convergence_uses_immutable_current_release() -> None:
    script = CONVERGENCE_WRAPPER.read_text(encoding="utf-8")
    assert "/opt/slurm-demo/current" in script
    assert "record-evidence" in script
    assert "--policy-revision" in script
    assert "--policy-lock-sha256" in script


def _stack_environment(tmp_path: Path) -> dict[str, str]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_executable(
        fake_bin / "az",
        """#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_AZ_LOG"
exit 99
""",
    )
    _write_executable(fake_bin / "terraform", "#!/usr/bin/env bash\nexit 99\n")
    template = tmp_path / "cyclecloud.json"
    parameters = tmp_path / "parameters.json"
    what_if = tmp_path / "what-if.json"
    template.write_text("{}")
    parameters.write_text("{}")
    what_if.write_text('{"changes":[]}')
    approval = tmp_path / "approval.json"
    approval.write_text(
        json.dumps(
            {
                "template_digest": "0" * 64,
                "parameters_digest": hashlib.sha256(
                    parameters.read_bytes()
                ).hexdigest(),
                "what_if_digest": hashlib.sha256(what_if.read_bytes()).hexdigest(),
                "approval_reference": "review-123",
            }
        )
    )
    return {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "FAKE_AZ_LOG": str(tmp_path / "az.log"),
        "CYCLECLOUD_TEMPLATE_FILE": str(template),
        "CYCLECLOUD_PARAMETERS_FILE": str(parameters),
        "CYCLECLOUD_WHAT_IF_FILE": str(what_if),
        "CYCLECLOUD_APPROVAL_FILE": str(approval),
        "CYCLECLOUD_EVIDENCE_DIR": str(tmp_path / "evidence"),
        "CYCLECLOUD_CLEANUP_PLAN_FILE": str(tmp_path / "cleanup.json"),
        "CYCLECLOUD_CLEANUP_APPROVAL_FILE": str(
            tmp_path / "cleanup-approval.json"
        ),
    }


def test_stack_apply_rejects_changed_template_before_azure(tmp_path: Path) -> None:
    environment = _stack_environment(tmp_path)
    result = subprocess.run(
        [str(STACK_SCRIPT), "apply"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "template digest" in result.stderr
    assert not Path(environment["FAKE_AZ_LOG"]).exists()


def _rbac_environment(tmp_path: Path) -> dict[str, str]:
    environment = _stack_environment(tmp_path)
    fake_bin = Path(environment["PATH"].split(":", 1)[0])
    terraform_log = tmp_path / "terraform.log"
    _write_executable(
        fake_bin / "terraform",
        """#!/usr/bin/env bash
printf '%s\n' "$*" >>"$FAKE_TERRAFORM_LOG"
exit 99
""",
    )
    plan = tmp_path / "cyclecloud-rbac.tfplan"
    plan.write_text("reviewed-rbac-plan")
    receipt = tmp_path / "entra-p1.json"
    receipt.write_text(
        json.dumps(
            {
                "result": "passed",
                "detailCode": "entra_p1_verified",
            }
        )
    )
    approval = tmp_path / "cyclecloud-rbac-approval.json"
    approval.write_text(
        json.dumps(
            {
                "plan_digest": hashlib.sha256(plan.read_bytes()).hexdigest(),
                "identity_phase": "post-create-rbac",
                "entra_p1_receipt_digest": hashlib.sha256(
                    receipt.read_bytes()
                ).hexdigest(),
                "approval_reference": "rbac-review-123",
            }
        )
    )
    environment.update(
        {
            "FAKE_TERRAFORM_LOG": str(terraform_log),
            "CYCLECLOUD_RBAC_PLAN_FILE": str(plan),
            "CYCLECLOUD_RBAC_APPROVAL_FILE": str(approval),
            "CYCLECLOUD_ENTRA_P1_RECEIPT_FILE": str(receipt),
        }
    )
    return environment


def test_rbac_apply_rejects_stale_plan_before_terraform(tmp_path: Path) -> None:
    environment = _rbac_environment(tmp_path)
    approval = Path(environment["CYCLECLOUD_RBAC_APPROVAL_FILE"])
    document = json.loads(approval.read_text())
    document["plan_digest"] = "0" * 64
    approval.write_text(json.dumps(document))

    result = subprocess.run(
        [str(STACK_SCRIPT), "rbac-apply"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "RBAC plan digest does not match" in result.stderr
    assert not Path(environment["FAKE_TERRAFORM_LOG"]).exists()


def test_rbac_apply_rejects_wrong_identity_phase_before_terraform(
    tmp_path: Path,
) -> None:
    environment = _rbac_environment(tmp_path)
    approval = Path(environment["CYCLECLOUD_RBAC_APPROVAL_FILE"])
    document = json.loads(approval.read_text())
    document["identity_phase"] = "foundation"
    approval.write_text(json.dumps(document))

    result = subprocess.run(
        [str(STACK_SCRIPT), "rbac-apply"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "identity phase does not match" in result.stderr
    assert not Path(environment["FAKE_TERRAFORM_LOG"]).exists()


def test_rbac_apply_rejects_changed_entra_receipt_before_terraform(
    tmp_path: Path,
) -> None:
    environment = _rbac_environment(tmp_path)
    approval = Path(environment["CYCLECLOUD_RBAC_APPROVAL_FILE"])
    document = json.loads(approval.read_text())
    document["entra_p1_receipt_digest"] = "0" * 64
    approval.write_text(json.dumps(document))

    result = subprocess.run(
        [str(STACK_SCRIPT), "rbac-apply"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 11
    assert "Entra ID P1 receipt digest does not match" in result.stderr
    assert not Path(environment["FAKE_TERRAFORM_LOG"]).exists()


def _cleanup_environment(
    tmp_path: Path,
    custom_role_count: int,
    vault_role_count: int,
) -> dict[str, str]:
    environment = _stack_environment(tmp_path)
    fake_bin = Path(environment["PATH"].split(":", 1)[0])
    cleanup_plan = Path(environment["CYCLECLOUD_CLEANUP_PLAN_FILE"])
    cleanup_plan.write_text('{"resources":["cyclecloud-vm"]}')
    cleanup_approval = Path(environment["CYCLECLOUD_CLEANUP_APPROVAL_FILE"])
    cleanup_approval.write_text(
        json.dumps(
            {
                "stack_snapshot_digest": hashlib.sha256(
                    cleanup_plan.read_bytes()
                ).hexdigest(),
                "approval_reference": "cleanup-review-123",
            }
        )
    )
    _write_executable(
        fake_bin / "terraform",
        """#!/usr/bin/env python3
import json
import sys

args = sys.argv[1:]
if args[-3:] == ["output", "-json", "cyclecloud_deployment"]:
    print(json.dumps({
        "resource_group_name": "demo-rg",
        "vm_name": "demo-cyclecloud",
    }))
elif args[-3:] == ["output", "-json", "cyclecloud_identity_rbac"]:
    print(json.dumps({
        "phase": "foundation",
        "post_create_rbac_enabled": False,
        "system_principal_id": None,
        "custom_role_assignment_scope": "/subscriptions/00000000-0000-0000-0000-000000000000",
        "custom_role_definition_id": "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/33333333-3333-4333-8333-333333333333",
        "key_vault_assignment_scope": "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/demo-rg/providers/Microsoft.KeyVault/vaults/demo-vault",
    }))
else:
    raise SystemExit(98)
""",
    )
    _write_executable(
        fake_bin / "az",
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ["FAKE_AZ_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
if args[:2] == ["account", "show"]:
    print("00000000-0000-0000-0000-000000000000")
elif args[:2] == ["vm", "show"]:
    print(json.dumps({
        "type": "SystemAssigned",
        "principalId": "22222222-2222-4222-8222-222222222222",
    }))
elif args[:3] == ["role", "assignment", "list"]:
    query = args[args.index("--query") + 1]
    if "roleDefinitionId" in query:
        print(os.environ["FAKE_CUSTOM_ROLE_COUNT"])
    else:
        print(os.environ["FAKE_VAULT_ROLE_COUNT"])
else:
    raise SystemExit(97)
""",
    )
    environment.update(
        {
            "FAKE_CUSTOM_ROLE_COUNT": str(custom_role_count),
            "FAKE_VAULT_ROLE_COUNT": str(vault_role_count),
        }
    )
    return environment


@pytest.mark.parametrize(
    ("custom_role_count", "vault_role_count"),
    [(1, 0), (0, 1)],
)
def test_cleanup_rejects_each_live_system_principal_assignment(
    tmp_path: Path,
    custom_role_count: int,
    vault_role_count: int,
) -> None:
    environment = _cleanup_environment(
        tmp_path,
        custom_role_count,
        vault_role_count,
    )

    result = subprocess.run(
        [str(STACK_SCRIPT), "cleanup"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 12
    assert "role assignments still exist" in result.stderr
    az_log = Path(environment["FAKE_AZ_LOG"]).read_text()
    assert "stack group delete" not in az_log


def _write_what_if_commands(
    environment: dict[str, str],
    changes: list[dict[str, str]],
) -> None:
    fake_bin = Path(environment["PATH"].split(":", 1)[0])
    what_if_result = fake_bin.parent / "what-if-result.json"
    what_if_result.write_text(json.dumps({"changes": changes}))
    environment["FAKE_WHAT_IF_RESULT"] = str(what_if_result)
    _write_executable(
        fake_bin / "terraform",
        """#!/usr/bin/env python3
import json
print(json.dumps({
    "resource_group_name": "demo-rg",
    "vm_name": "demo-cyclecloud",
}))
""",
    )
    _write_executable(
        fake_bin / "az",
        """#!/usr/bin/env python3
import os
from pathlib import Path
import sys

args = sys.argv[1:]
if args[:2] == ["account", "show"]:
    print("00000000-0000-0000-0000-000000000000")
elif args[:3] == ["deployment", "group", "validate"]:
    pass
elif args[:3] == ["deployment", "group", "what-if"]:
    print(Path(os.environ["FAKE_WHAT_IF_RESULT"]).read_text())
else:
    raise SystemExit(9)
""",
    )


def test_what_if_ignores_azure_ignore_records(tmp_path: Path) -> None:
    environment = _stack_environment(tmp_path)
    _write_what_if_commands(
        environment,
        [
            {
                "changeType": "Ignore",
                "resourceId": (
                    "/subscriptions/example/resourceGroups/demo-rg/"
                    "providers/Microsoft.Network/virtualNetworks/demo"
                ),
            },
            {
                "changeType": "Create",
                "resourceId": (
                    "/subscriptions/example/resourceGroups/demo-rg/"
                    "providers/Microsoft.Compute/virtualMachines/demo-cyclecloud"
                ),
            },
        ],
    )

    result = subprocess.run(
        [str(STACK_SCRIPT), "what-if"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr


def test_what_if_rejects_actionable_non_vm_changes(tmp_path: Path) -> None:
    environment = _stack_environment(tmp_path)
    _write_what_if_commands(
        environment,
        [
            {
                "changeType": "Modify",
                "resourceId": (
                    "/subscriptions/example/resourceGroups/demo-rg/"
                    "providers/Microsoft.Network/virtualNetworks/demo"
                ),
            },
            {
                "changeType": "Create",
                "resourceId": (
                    "/subscriptions/example/resourceGroups/demo-rg/"
                    "providers/Microsoft.Compute/virtualMachines/demo-cyclecloud"
                ),
            },
        ],
    )

    result = subprocess.run(
        [str(STACK_SCRIPT), "what-if"],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0


def _password_evidence() -> dict[str, object]:
    return {
        "schemaVersion": 1,
        "status": "generated",
        "policyProfile": "interactive-admin-v1",
        "targets": [
            {
                "target": "windows",
                "account": "windowsadmin",
                "secretName": "windows-admin-password",
                "disposition": "generated",
            },
            {
                "target": "cyclecloud",
                "account": "hpcadmin",
                "secretName": "cyclecloud-admin-password",
                "disposition": "generated",
            },
        ],
        "newValuePolicyValidated": True,
        "uniquenessValidated": True,
        "protectedModesValidated": True,
        "completedAt": "2026-10-23T21:00:00Z",
    }


def _secret_writer_environment(
    tmp_path: Path,
    password_evidence: dict[str, object] | None = None,
) -> tuple[dict[str, str], Path]:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    _write_executable(
        fake_bin / "terraform",
        """#!/usr/bin/env bash
cat <<'JSON'
{"key_vault_private_name":"demo-vault.privatelink.vaultcore.azure.net"}
JSON
""",
    )
    _write_executable(
        fake_bin / "az",
        """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import sys

args = sys.argv[1:]
with Path(os.environ["FAKE_AZ_LOG"]).open("a") as log:
    log.write(json.dumps(args) + "\\n")
name = args[args.index("--name") + 1]
print(json.dumps({"id": f"https://demo-vault.vault.azure.net/secrets/{name}/version", "name": name}))
""",
    )
    protected_files = []
    for name in (
        "cyclecloud",
        "scheduler",
        "windows",
        "cyclecloud-admin",
        "cyclecloud-pfx",
        "cyclecloud-pfx-password",
        "cyclecloud-ca",
        "chef-license",
    ):
        path = tmp_path / name
        path.write_text(f"secret-{name}")
        path.chmod(0o600)
        protected_files.append(path)
    evidence = tmp_path / "secret-references.json"
    password_evidence_path = tmp_path / "admin-password-evidence.json"
    if password_evidence is not None:
        password_evidence_path.write_text(json.dumps(password_evidence))
        password_evidence_path.chmod(0o600)
    environment = {
        **os.environ,
        "PATH": f"{fake_bin}:{os.environ['PATH']}",
        "FAKE_AZ_LOG": str(tmp_path / "az.log"),
        "CYCLECLOUD_SSH_PRIVATE_KEY_FILE": str(protected_files[0]),
        "SCHEDULER_SSH_PRIVATE_KEY_FILE": str(protected_files[1]),
        "WINDOWS_ADMIN_PASSWORD_FILE": str(protected_files[2]),
        "CYCLECLOUD_ADMIN_PASSWORD_FILE": str(protected_files[3]),
        "CYCLECLOUD_TLS_PFX_FILE": str(protected_files[4]),
        "CYCLECLOUD_TLS_PFX_PASSWORD_FILE": str(protected_files[5]),
        "CYCLECLOUD_TLS_CA_FILE": str(protected_files[6]),
        "CHEF_LICENSE_ID_FILE": str(protected_files[7]),
        "ADMIN_PASSWORD_EVIDENCE_FILE": str(password_evidence_path),
        "ADMIN_SECRET_EVIDENCE_FILE": str(evidence),
    }
    return environment, evidence


def test_secret_writer_records_references_without_values(tmp_path: Path) -> None:
    environment, evidence = _secret_writer_environment(
        tmp_path,
        _password_evidence(),
    )

    result = subprocess.run(
        [str(SECRET_SCRIPT)],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    assert "secret-" not in evidence.read_text()
    calls = [
        json.loads(line)
        for line in Path(environment["FAKE_AZ_LOG"]).read_text().splitlines()
    ]
    assert len(calls) == 8
    assert all("--file" in call and "--value" not in call for call in calls)


@pytest.mark.parametrize(
    "password_evidence",
    [
        None,
        {**_password_evidence(), "status": "failed"},
        {**_password_evidence(), "uniquenessValidated": False},
        {
            **_password_evidence(),
            "targets": [
                {
                    "target": "windows",
                    "account": "wrong-account",
                    "secretName": "windows-admin-password",
                    "disposition": "generated",
                },
                _password_evidence()["targets"][1],
            ],
        },
    ],
)
def test_secret_writer_rejects_unaccepted_password_evidence_before_azure(
    tmp_path: Path,
    password_evidence: dict[str, object] | None,
) -> None:
    environment, evidence = _secret_writer_environment(
        tmp_path,
        password_evidence,
    )

    result = subprocess.run(
        [str(SECRET_SCRIPT)],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert not Path(environment["FAKE_AZ_LOG"]).exists()
    assert not evidence.exists()


def test_bootstrap_secret_generator_creates_protected_complete_material(
    tmp_path: Path,
) -> None:
    admin_password = tmp_path / "admin-password"
    admin_password.write_text("existing-admin-password")
    admin_password.chmod(0o600)
    environment = {
        **os.environ,
        "CYCLECLOUD_PRIVATE_NAME": "cyclecloud.internal",
        "CYCLECLOUD_ADMIN_PASSWORD_FILE": str(admin_password),
        "CYCLECLOUD_TLS_CA_FILE": str(tmp_path / "ca.crt"),
        "CYCLECLOUD_TLS_PFX_FILE": str(tmp_path / "server.pfx"),
        "CYCLECLOUD_TLS_PFX_PASSWORD_FILE": str(tmp_path / "pfx-password"),
    }

    result = subprocess.run(
        [str(BOOTSTRAP_SECRET_SCRIPT)],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode == 0, result.stderr
    for key in (
        "CYCLECLOUD_ADMIN_PASSWORD_FILE",
        "CYCLECLOUD_TLS_CA_FILE",
        "CYCLECLOUD_TLS_PFX_FILE",
        "CYCLECLOUD_TLS_PFX_PASSWORD_FILE",
    ):
        path = Path(environment[key])
        assert path.is_file()
        assert path.stat().st_mode & 0o077 == 0


def test_bootstrap_secret_generator_does_not_create_admin_password(
    tmp_path: Path,
) -> None:
    admin_password = tmp_path / "admin-password"
    environment = {
        **os.environ,
        "CYCLECLOUD_PRIVATE_NAME": "cyclecloud.internal",
        "CYCLECLOUD_ADMIN_PASSWORD_FILE": str(admin_password),
        "CYCLECLOUD_TLS_CA_FILE": str(tmp_path / "ca.crt"),
        "CYCLECLOUD_TLS_PFX_FILE": str(tmp_path / "server.pfx"),
        "CYCLECLOUD_TLS_PFX_PASSWORD_FILE": str(tmp_path / "pfx-password"),
    }

    result = subprocess.run(
        [str(BOOTSTRAP_SECRET_SCRIPT)],
        cwd=ROOT,
        env=environment,
        check=False,
        capture_output=True,
        text=True,
    )

    assert result.returncode != 0
    assert not admin_password.exists()
