from pathlib import Path
import re

ROOT = Path(__file__).parents[2]


def terraform_file(name: str) -> str:
    return (ROOT / "terraform" / name).read_text()


def test_private_hosts_use_standard_public_bastion() -> None:
    source = terraform_file("network.tf") + terraform_file("security.tf") + terraform_file("compute.tf")
    assert re.search(
        r"public_network_access_enabled\s*=\s*var\.key_vault_provisioning_access_enabled",
        source,
    )
    assert (
        "var.key_vault_provisioning_access_enabled "
        "? var.key_vault_provisioning_ipv4_cidrs : []"
    ) in source
    assert re.search(r'sku\s*=\s*"Standard"', source)
    assert re.search(r"private_only_enabled\s*=\s*false", source)
    assert re.search(r"session_recording_enabled\s*=\s*false", source)
    assert re.search(r"tunneling_enabled\s*=\s*true", source)
    assert re.search(r"create_public_ip\s*=\s*true", source)
    assert re.search(r"create_public_ip_address\s*=\s*false", source)


def test_vm_subnets_use_regional_nat_gateways() -> None:
    source = terraform_file("network.tf")
    assert source.count('source  = "Azure/avm-res-network-natgateway/azurerm"') == 2
    assert source.count('version = "0.3.2"') >= 2

    source_gateway = re.search(
        r'(?ms)^module "source_nat_gateway" \{(.*?)^\}',
        source,
    )
    burst_gateway = re.search(
        r'(?ms)^module "burst_nat_gateway" \{(.*?)^\}',
        source,
    )
    assert source_gateway
    assert burst_gateway
    for gateway in (source_gateway.group(1), burst_gateway.group(1)):
        assert re.search(r'sku_name\s*=\s*"Standard"', gateway)
        assert "public_ips = {" in gateway

    management = re.search(r"(?ms)^    management = \{(.*?)^    \}", source)
    access = re.search(r"(?ms)^    access = \{(.*?)^    \}", source)
    compute = re.search(r"(?ms)^    compute = \{(.*?)^    \}", source)
    private_endpoint = re.search(
        r"(?ms)^    private_endpoint = \{(.*?)^    \}",
        source,
    )
    bastion = re.search(r"(?ms)^    bastion = \{(.*?)^    \}", source)
    assert all((management, access, compute, private_endpoint, bastion))
    assert "id = module.source_nat_gateway.resource_id" in management.group(1)
    assert "id = module.source_nat_gateway.resource_id" in access.group(1)
    assert "id = module.burst_nat_gateway.resource_id" in compute.group(1)
    assert "nat_gateway" not in private_endpoint.group(1)
    assert "nat_gateway" not in bastion.group(1)


def test_explicit_cross_region_rules_and_default_deny() -> None:
    source = terraform_file("network.tf") + terraform_file("security.tf")
    for port in ("22", "3389", "443", "9443", "2049", "6817", "6818"):
        assert f'"{port}"' in source
    assert "DenyAllInbound" in source


def test_windows_vm_is_the_only_bastion_jump_host() -> None:
    source = terraform_file("network.tf")
    rule_pattern = r"(?ms)^    {name} = \{{\n(.*?)^    \}}"

    def rule(name: str) -> str:
        match = re.search(rule_pattern.format(name=name), source)
        assert match, f"missing {name} rule"
        return match.group(1)

    bastion_rdp = rule("bastion_rdp")
    assert "source_address_prefix      = local.source_subnets.bastion" in bastion_rdp
    assert "destination_address_prefix = local.source_subnets.access" in bastion_rdp
    assert 'destination_port_range     = "3389"' in bastion_rdp
    assert "bastion_ssh" not in source

    jump_host_ssh = rule("jump_host_ssh")
    assert "source_address_prefix      = local.source_subnets.access" in jump_host_ssh
    assert "destination_address_prefix = local.source_subnets.management" in jump_host_ssh
    assert 'destination_port_range     = "22"' in jump_host_ssh

    jump_host_https = rule("jump_host_cyclecloud_https")
    assert "source_address_prefix      = local.source_subnets.access" in jump_host_https
    assert "destination_address_prefix = local.source_subnets.management" in jump_host_https
    assert 'destination_port_range     = "443"' in jump_host_https

    scheduler_api = rule("scheduler_cyclecloud_api")
    assert "source_address_prefix      = local.source_subnets.management" in scheduler_api
    assert "destination_address_prefix = local.source_subnets.management" in scheduler_api
    assert 'destination_port_range     = "9443"' in scheduler_api

    bastion_sourced_rules = [
        match.group(1)
        for match in re.finditer(
            r"(?ms)^    [a-z0-9_]+ = \{\n(.*?)^    \}",
            source,
        )
        if "source_address_prefix      = local.source_subnets.bastion"
        in match.group(1)
    ]
    assert bastion_sourced_rules == [bastion_rdp]


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
