from pathlib import Path


ROOT = Path(__file__).parents[2]


def test_scheduler_bootstrap_stages_without_autonomous_convergence() -> None:
    bootstrap = (ROOT / "chef/bootstrap/linux.sh").read_text()
    assert "state=waiting_dependencies" in bootstrap
    assert "converge-scheduler.sh" not in bootstrap
    assert "systemctl enable" not in bootstrap
    assert "while " not in bootstrap


def test_chef_download_uses_protected_commercial_license() -> None:
    bootstrap = (ROOT / "chef/bootstrap/linux.sh").read_text()
    scheduler = (ROOT / "terraform/compute.tf").read_text()
    cyclecloud = (ROOT / "infra/cyclecloud/bootstrap.sh").read_text()

    assert "https://packages.chef.io/" not in bootstrap
    assert "chefdownload-commercial.chef.io/stable/chef/download" in bootstrap
    assert '--config "$curl_config"' in bootstrap
    assert "license_id" not in scheduler
    assert "--name, chef-license-id" in scheduler
    assert "CHEF_LICENSE_ID_FILE=/run/chef-license-id" in scheduler
    assert 'download_secret chef-license-id "$secret_dir/chef-license-id"' in cyclecloud


def test_scheduler_convergence_is_explicit_and_reboot_safe() -> None:
    wrapper = (ROOT / "chef/bin/converge-scheduler.sh").read_text()
    workflow = (ROOT / "tests/end-to-end/converge_linux_roles.sh").read_text()
    assert "authorization" in wrapper
    assert "chef-client --local-mode" in wrapper
    assert "systemd" not in wrapper.lower()
    assert "cron" not in wrapper.lower()
    assert "verify-reboot" in workflow
    assert "attempt" in workflow


def test_reboot_evidence_covers_both_persistent_vms_without_secret_values() -> None:
    workflow = (ROOT / "tests/end-to-end/converge_linux_roles.sh").read_text()
    assert "cyclecloud-reboot-receipt.json" in workflow
    assert "scheduler-reboot-receipt.json" in workflow
    assert "publicCredentialFingerprint" in workflow
    assert "clusterCount" in workflow
    assert "evidenceSetDigest" in workflow
    assert "explicitPolicyOnly" in workflow
    assert "persistent VM reboot evidence is unchanged" in workflow
