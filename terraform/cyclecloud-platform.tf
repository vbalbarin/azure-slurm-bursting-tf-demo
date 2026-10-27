locals {
  cyclecloud_chef_manifest_base64      = base64encode(local.chef_role_payloads.cyclecloud.manifest_json)
  cyclecloud_chef_specification_json   = jsonencode(local.chef_node_specifications.cyclecloud)
  cyclecloud_chef_specification_base64 = base64encode(local.cyclecloud_chef_specification_json)
  cyclecloud_chef_lock_path            = "${path.module}/../chef/policyfiles/cyclecloud.lock.json"
  cyclecloud_chef_lock_base64          = filebase64(local.cyclecloud_chef_lock_path)
  cyclecloud_chef_archive_padding = (
    endswith(local.chef_role_payloads.cyclecloud.policy_archive_base64, "==") ? 2 :
    endswith(local.chef_role_payloads.cyclecloud.policy_archive_base64, "=") ? 1 : 0
  )
  cyclecloud_chef_archive_size = (
    length(local.chef_role_payloads.cyclecloud.policy_archive_base64) * 3 / 4 -
    local.cyclecloud_chef_archive_padding
  )
  cyclecloud_chef_decoded_size = (
    local.cyclecloud_chef_archive_size +
    length(local.chef_role_payloads.cyclecloud.manifest_json) +
    length(local.cyclecloud_chef_specification_json) +
    length(file(local.cyclecloud_chef_lock_path))
  )
  cyclecloud_custom_data = base64encode(templatefile(
    "${path.module}/../infra/cyclecloud/custom-data.yaml.tftpl",
    {
      bootstrap_script            = file("${path.module}/../infra/cyclecloud/bootstrap.sh")
      admin_username              = var.cyclecloud_admin_username
      subscription_id             = var.subscription_id
      tenant_id                   = var.tenant_id
      vm_resource_id              = local.cyclecloud_vm_resource_id
      compute_resource_group_name = module.cyclecloud_compute_resource_group.name
      burst_region                = var.burst_region
      locker_storage_name         = module.cyclecloud_locker_storage.name
      locker_storage_resource_id  = module.cyclecloud_locker_storage.resource_id
      locker_identity_resource_id = module.cyclecloud_locker_identity.resource_id
      key_vault_name              = local.names.key_vault
      key_vault_resource_id       = module.key_vault.resource_id
      private_name                = "${local.names.cyclecloud}.${local.private_dns_zones.cyclecloud}"
      source_revision             = jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).sourceRevision
      custom_role_definition_id   = azurerm_role_definition.cyclecloud_orchestrator.role_definition_resource_id
      custom_role_digest          = local.cyclecloud_custom_role_definition_digest
      custom_role_scope           = local.cyclecloud_subscription_scope
      chef_payload_base64         = local.chef_role_payloads.cyclecloud.policy_archive_base64
      chef_manifest_base64        = local.cyclecloud_chef_manifest_base64
      chef_specification_base64   = local.cyclecloud_chef_specification_base64
      chef_policy_lock_base64     = local.cyclecloud_chef_lock_base64
      chef_payload_sha256         = jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).artifacts[index(jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).artifacts[*].kind, "policy")].sha256
      chef_manifest_sha256        = sha256(local.chef_role_payloads.cyclecloud.manifest_json)
      chef_specification_sha256   = sha256(local.cyclecloud_chef_specification_json)
      chef_policy_lock_sha256     = filesha256(local.cyclecloud_chef_lock_path)
    }
  ))
}

check "cyclecloud_chef_payload_size" {
  assert {
    condition     = local.cyclecloud_chef_decoded_size <= 60000
    error_message = "The decoded aggregate CycleCloud Chef payload must not exceed 60000 bytes."
  }
}

module "cyclecloud_locker_identity" {
  source  = "Azure/avm-res-managedidentity-userassignedidentity/azurerm"
  version = "0.5.3"

  location            = var.source_region
  name                = local.names.locker_identity
  resource_group_name = module.resource_group.name
  enable_telemetry    = false
  tags                = local.common_tags
}

module "cyclecloud_compute_resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location         = var.burst_region
  name             = local.cyclecloud_compute_resource_group_name
  enable_telemetry = false
  tags             = local.common_tags
}

module "cyclecloud_locker_storage" {
  source  = "Azure/avm-res-storage-storageaccount/azurerm"
  version = "0.10.0"

  location                      = var.source_region
  name                          = local.names.locker_storage
  parent_id                     = module.resource_group.resource_id
  account_replication_type      = "LRS"
  shared_access_key_enabled     = false
  public_network_access_enabled = false
  enable_telemetry              = false
  tags                          = local.common_tags

  containers = {
    cyclecloud = {
      name = "cyclecloud"
    }
  }

  role_assignments = {
    locker_blob_data_reader = {
      role_definition_id_or_name = "Storage Blob Data Reader"
      principal_id               = module.cyclecloud_locker_identity.principal_id
      principal_type             = "ServicePrincipal"
    }
  }

  private_endpoints = {
    blob = {
      name                          = "${local.names.locker_storage}-blob-pe"
      subnet_resource_id            = module.source_vnet.subnets["private_endpoint"].resource_id
      subresource_name              = "blob"
      private_dns_zone_resource_ids = [module.blob_private_dns.resource_id]
    }
  }
}
