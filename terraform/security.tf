module "key_vault_private_dns" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = local.private_dns_zones.key_vault
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.common_tags

  virtual_network_links = {
    source = {
      name               = "keyvault-source-link"
      virtual_network_id = module.source_vnet.resource_id
    }
    burst = {
      name               = "keyvault-burst-link"
      virtual_network_id = module.burst_vnet.resource_id
    }
  }
}

module "cyclecloud_private_dns" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = local.private_dns_zones.cyclecloud
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.common_tags

  virtual_network_links = {
    source = {
      name               = "cyclecloud-source-link"
      virtual_network_id = module.source_vnet.resource_id
    }
    burst = {
      name               = "cyclecloud-burst-link"
      virtual_network_id = module.burst_vnet.resource_id
    }
  }
}

module "key_vault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.11.0"

  location                      = var.source_region
  name                          = local.names.key_vault
  resource_group_name           = module.resource_group.name
  tenant_id                     = var.tenant_id
  public_network_access_enabled = false
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  enable_telemetry              = false
  tags                          = local.common_tags

  network_acls = {
    bypass         = "None"
    default_action = "Deny"
  }

  role_assignments = {
    for id in var.operator_group_object_ids : id => {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = id
      principal_type             = "Group"
    }
  }

  private_endpoints = {
    vault = {
      name                          = "${local.names.key_vault}-pe"
      subnet_resource_id            = module.source_vnet.subnets["private_endpoint"].resource_id
      private_dns_zone_resource_ids = [module.key_vault_private_dns.resource_id]
    }
  }

  diagnostic_settings = {
    audit = {
      name                           = "key-vault-audit"
      workspace_resource_id          = module.log_analytics.resource_id
      log_groups                     = ["audit"]
      metric_categories              = ["AllMetrics"]
      log_analytics_destination_type = "Dedicated"
    }
  }
}

module "bastion" {
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "0.9.0"

  location                  = var.source_region
  name                      = local.names.bastion
  parent_id                 = module.resource_group.resource_id
  sku                       = "Premium"
  private_only_enabled      = true
  session_recording_enabled = true
  tunneling_enabled         = false
  enable_telemetry          = false
  tags                      = local.common_tags

  ip_configuration = {
    name             = "private"
    subnet_id        = module.source_vnet.subnets["bastion"].resource_id
    create_public_ip = false
  }
}
