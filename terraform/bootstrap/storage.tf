locals {
  container_role_assignments = merge(
    {
      operator_group = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = var.operator_group_object_id
        principal_type             = "Group"
        description                = "Terraform state access for approved operators."
      }
    },
    var.workload_identity_object_id == null ? {} : {
      workload_identity = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = var.workload_identity_object_id
        principal_type             = "ServicePrincipal"
        description                = "Terraform state access for approved automation."
      }
    }
  )
}

module "storage" {
  count = var.ownership_mode == "managed" ? 1 : 0

  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  location  = var.location
  name      = local.storage_account_name
  parent_id = module.resource_group[0].resource_id
  tags      = var.tags

  account_kind                      = "StorageV2"
  account_replication_type          = "LRS"
  account_tier                      = "Standard"
  allow_nested_items_to_be_public   = false
  default_to_oauth_authentication   = true
  https_traffic_only_enabled        = true
  infrastructure_encryption_enabled = true
  local_user_enabled                = false
  min_tls_version                   = "TLS1_2"
  nfsv3_enabled                     = false
  public_network_access_enabled     = var.network_mode == "restricted_public"
  sftp_enabled                      = false
  shared_access_key_enabled         = false

  network_rules = var.network_mode == "restricted_public" ? {
    bypass                     = ["None"]
    default_action             = "Deny"
    ip_rules                   = local.storage_ip_rules
    virtual_network_subnet_ids = []
  } : null

  blob_properties = {
    versioning_enabled = true
    delete_retention_policy = {
      allow_permanent_delete = false
      days                   = 7
      enabled                = true
    }
    container_delete_retention_policy = {
      allow_permanent_delete = false
      days                   = 7
      enabled                = true
    }
  }

  containers = {
    state = {
      name             = local.container_name
      public_access    = "None"
      role_assignments = local.container_role_assignments
    }
  }

  private_endpoints = var.network_mode == "private" ? {
    blob = {
      name                          = local.private_endpoint_name
      subnet_resource_id            = var.private_endpoint_subnet_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [var.private_dns_zone_id]
      tags                          = var.tags
    }
  } : {}

  lock = var.lifecycle_action == "unlock" ? null : {
    kind = "CanNotDelete"
    name = "lock-${local.storage_account_name}"
  }
}
