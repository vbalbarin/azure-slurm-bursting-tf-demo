from pathlib import Path
import re

ROOT = Path(__file__).parents[2]


def terraform_file(name: str) -> str:
    return (ROOT / "terraform" / name).read_text()


def test_private_only_management_surfaces() -> None:
    source = terraform_file("network.tf") + terraform_file("security.tf") + terraform_file("compute.tf")
    assert re.search(
        r"public_network_access_enabled\s*=\s*var\.key_vault_provisioning_access_enabled",
        source,
    )
    assert (
        "var.key_vault_provisioning_access_enabled "
        "? var.key_vault_provisioning_ipv4_cidrs : []"
    ) in source
    assert re.search(r"private_only_enabled\s*=\s*true", source)
    assert re.search(r"session_recording_enabled\s*=\s*false", source)
    assert re.search(r"tunneling_enabled\s*=\s*true", source)
    assert re.search(r"create_public_ip_address\s*=\s*false", source)


def test_explicit_cross_region_rules_and_default_deny() -> None:
    source = terraform_file("network.tf") + terraform_file("security.tf")
    for port in ("22", "3389", "443", "9443", "2049", "6817", "6818"):
        assert f'"{port}"' in source
    assert "DenyAllInbound" in source


def test_least_privilege_identity_and_audit_retention() -> None:
    source = terraform_file("security.tf") + terraform_file("monitoring.tf")
    assert re.search(r'principal_type\s*=\s*"Group"', source)
    assert "system_assigned = true" in terraform_file("compute.tf")
    assert "log_analytics_workspace_retention_in_days = 90" in source


def test_key_vault_provisioning_access_is_exact_and_bounded() -> None:
    variables = terraform_file("variables.tf")
    locals_source = terraform_file("locals.tf")
    security = terraform_file("security.tf")
    assert 'endswith(var.key_vault_provisioning_ipv4_cidrs[0], "/32")' in variables
    assert 'var.key_vault_provisioning_ipv4_cidrs[0] != "0.0.0.0/32"' in variables
    assert "length(var.key_vault_provisioning_ipv4_cidrs) == 0" in variables
    assert 'SecurityControl = "Ignore"' in locals_source
    assert "tags                          = local.key_vault_tags" in security
    common_tags = re.search(r"common_tags\s*=\s*\{(.*?)\n\s*\}", locals_source, re.DOTALL)
    assert common_tags
    assert "SecurityControl" not in common_tags.group(1)


def test_windows_hotpatch_uses_platform_orchestration() -> None:
    source = terraform_file("compute.tf")
    assert re.search(r'patch_mode\s*=\s*"AutomaticByPlatform"', source)
    assert re.search(r'patch_assessment_mode\s*=\s*"AutomaticByPlatform"', source)
