from pathlib import Path
import re

ROOT = Path(__file__).parents[2]


def terraform_sources() -> str:
    return "\n".join(path.read_text() for path in (ROOT / "terraform").glob("*.tf"))


def test_no_direct_azure_resources() -> None:
    source = terraform_sources()
    assert not re.search(r'resource\s+"(?:azurerm|azapi)_', source)


def test_modules_are_remote_pinned_avms() -> None:
    source = terraform_sources()
    blocks = re.findall(r'module\s+"[^"]+"\s*\{(.*?)\n\}', source, re.DOTALL)
    for block in blocks:
        assert re.search(r'source\s*=\s*"Azure/avm-', block)
        assert re.search(r'version\s*=\s*"\d+\.\d+\.\d+"', block)


def test_no_public_ip_or_public_key_vault() -> None:
    source = terraform_sources()
    assert "public_ip_address_id" not in source
    assert not re.search(r'public_network_access_enabled\s*=\s*true', source)


def test_secret_outputs_are_sensitive() -> None:
    source = (ROOT / "terraform" / "outputs.tf").read_text() if (ROOT / "terraform" / "outputs.tf").exists() else ""
    for block in re.findall(r'output\s+"([^"]*(?:secret|credential|password|key)[^"]*)"\s*\{(.*?)\n\}', source, re.DOTALL | re.IGNORECASE):
        assert re.search(r'sensitive\s*=\s*true', block[1])


def test_chef_has_no_azure_control_plane_commands() -> None:
    forbidden = re.compile(r"\b(?:az\s+(?:group|network|vm|resource)\s+(?:create|delete|update)|terraform\s+(?:apply|destroy))\b")
    for path in (ROOT / "chef").rglob("*"):
        if path.is_file():
            assert not forbidden.search(path.read_text(errors="ignore")), path
