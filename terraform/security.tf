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

  a_records = {
    cyclecloud = {
      name         = local.names.cyclecloud
      ttl          = 300
      ip_addresses = [module.cyclecloud_nic.resource.private_ip_address]
    }

  }

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

module "scheduler_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.3"

  location            = var.source_region
  name                = local.names.scheduler_identity
  resource_group_name = module.resource_group.name
  enable_telemetry    = false
  tags                = local.common_tags
}

module "blob_private_dns" {
  source  = "Azure/avm-res-network-privatednszone/azurerm"
  version = "0.5.0"

  domain_name      = local.private_dns_zones.blob
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.common_tags

  virtual_network_links = {
    source = {
      name               = "blob-source-link"
      virtual_network_id = module.source_vnet.resource_id
    }
    burst = {
      name               = "blob-burst-link"
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
  public_network_access_enabled = var.key_vault_provisioning_access_enabled
  purge_protection_enabled      = true
  soft_delete_retention_days    = 90
  enable_telemetry              = false
  tags                          = local.key_vault_tags

  network_acls = {
    bypass         = "None"
    default_action = "Deny"
    ip_rules       = var.key_vault_provisioning_access_enabled ? var.key_vault_provisioning_ipv4_cidrs : []
  }

  role_assignments = merge({
    for id in var.operator_group_object_ids : id => {
      role_definition_id_or_name = "Key Vault Secrets Officer"
      principal_id               = id
      principal_type             = "Group"
    }
    }, {
    scheduler_secrets_user = {
      role_definition_id_or_name = local.scheduler_key_vault_role
      principal_id               = module.scheduler_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  })

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

module "bastion_public_ip" {
  source  = "Azure/avm-res-network-publicipaddress/azurerm"
  version = "0.2.1"

  allocation_method   = "Static"
  enable_telemetry    = false
  location            = var.source_region
  name                = "${local.names.bastion}-pip"
  resource_group_name = module.resource_group.name
  sku                 = "Standard"
  sku_tier            = "Regional"
  tags                = local.common_tags
  zones               = [1, 2, 3]

  ip_tags = {
    FirstPartyUsage = "/Unprivileged"
  }
}

module "bastion" {
  source  = "Azure/avm-res-network-bastionhost/azurerm"
  version = "0.9.0"

  location                  = var.source_region
  name                      = local.names.bastion
  parent_id                 = module.resource_group.resource_id
  sku                       = "Standard"
  private_only_enabled      = false
  session_recording_enabled = false
  tunneling_enabled         = true
  enable_telemetry          = false
  tags                      = local.common_tags

  ip_configuration = {
    name                 = "public"
    subnet_id            = module.source_vnet.subnets["bastion"].resource_id
    create_public_ip     = false
    public_ip_address_id = module.bastion_public_ip.resource_id
  }
}
