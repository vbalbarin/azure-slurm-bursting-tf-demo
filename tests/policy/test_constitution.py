from pathlib import Path
import re

ROOT = Path(__file__).parents[2]


def terraform_sources() -> str:
    return "\n".join(
        path.read_text()
        for path in (ROOT / "terraform").rglob("*.tf")
        if ".terraform" not in path.parts
    )


def test_no_direct_azure_resources() -> None:
    source = terraform_sources()
    assert not re.search(r'resource\s+"(?:azurerm|azapi)_', source)


def test_modules_are_remote_pinned_avms() -> None:
    source = terraform_sources()
    blocks = re.findall(r'module\s+"[^"]+"\s*\{(.*?)\n\}', source, re.DOTALL)
    for block in blocks:
        assert re.search(r'source\s*=\s*"Azure/avm-', block)
        assert re.search(r'version\s*=\s*"\d+\.\d+\.\d+"', block)


def test_bootstrap_uses_no_secret_backend_authentication() -> None:
    bootstrap = ROOT / "terraform" / "bootstrap"
    source = "\n".join(
        path.read_text() for path in bootstrap.glob("*.tf*") if path.is_file()
    )
    for forbidden in ("access_key", "sas_token"):
        assert not re.search(rf"(?m)^\s*{forbidden}\s*=", source)
    assert "lookup_blob_endpoint" not in source


def test_bootstrap_has_no_unrestricted_public_fallback() -> None:
    bootstrap = ROOT / "terraform" / "bootstrap"
    source = "\n".join(path.read_text() for path in bootstrap.glob("*.tf"))
    assert 'cidr != "0.0.0.0/0"' in source
    assert "0.0.0.0/0" not in (bootstrap / "storage.tf").read_text()


def test_no_vm_public_ip_or_unrestricted_public_key_vault() -> None:
    source = terraform_sources()
    assert "public_ip_address_id" not in source
    assert "create_public_ip_address      = false" in source
    assert not re.search(r'public_network_access_enabled\s*=\s*true', source)


def test_cyclecloud_bicep_exception_is_vm_only() -> None:
    bicep_files = list((ROOT / "infra").rglob("*.bicep"))
    assert bicep_files == [ROOT / "infra" / "cyclecloud" / "main.bicep"]
    source = bicep_files[0].read_text()
    resources = re.findall(r"(?m)^resource\s+\w+\s+'([^']+)'", source)
    assert resources == ["Microsoft.Compute/virtualMachines@2024-11-01"]
    assert "lun: 0" in source
    assert "createOption: 'FromImage'" in source
    assert "id: nicResourceId" in source
    assert "azurecyclecloud" not in source


def test_cyclecloud_stack_has_digest_gates_and_delete_all_cleanup() -> None:
    script = ROOT / "tests" / "end-to-end" / "cyclecloud_stack.sh"
    source = script.read_text()
    assert script.stat().st_mode & 0o111
    for field in ("template_digest", "parameters_digest", "what_if_digest"):
        assert field in source
    assert source.count("--action-on-unmanage deleteAll") == 2
    assert "--resources-without-delete-support fail" in source


def test_admin_secret_writer_uses_files_and_redacts_values() -> None:
    script = ROOT / "tests" / "end-to-end" / "store_admin_secrets.sh"
    source = script.read_text()
    assert script.stat().st_mode & 0o111
    assert "--file" in source
    assert "--value" not in source
    assert "--query '{id:id,name:name}'" in source


def test_secret_outputs_are_sensitive() -> None:
    source = (ROOT / "terraform" / "outputs.tf").read_text() if (ROOT / "terraform" / "outputs.tf").exists() else ""
    for block in re.findall(r'output\s+"([^"]*(?:secret|credential|password|key)[^"]*)"\s*\{(.*?)\n\}', source, re.DOTALL | re.IGNORECASE):
        assert re.search(r'sensitive\s*=\s*true', block[1])


def test_chef_has_no_azure_control_plane_commands() -> None:
    forbidden = re.compile(r"\b(?:az\s+(?:group|network|vm|resource)\s+(?:create|delete|update)|terraform\s+(?:apply|destroy))\b")
    for path in (ROOT / "chef").rglob("*"):
        if path.is_file():
            assert not forbidden.search(path.read_text(errors="ignore")), path
