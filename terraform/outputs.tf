output "inventory" {
  description = "Secret-free private environment inventory."
  value = {
    environment_name           = var.environment_name
    source_region              = var.source_region
    burst_region               = var.burst_region
    burst_zone                 = var.burst_zone
    alternate_burst_placements = var.alternate_burst_placements
    planned_role_counts = {
      cyclecloud    = var.cyclecloud_vm_count
      scheduler     = var.scheduler_vm_count
      windows_admin = var.windows_vm_count
      burst_compute = var.burst_node_count
    }
    cluster_name = var.cluster_name
    private_hosts = {
      cyclecloud = {
        name            = local.names.cyclecloud
        private_address = module.cyclecloud_nic.resource.private_ip_address
      }
      scheduler = {
        name            = local.names.scheduler
        private_address = module.scheduler_vm.network_interfaces["primary"].private_ip_address
      }
      windows_admin = {
        name            = local.names.windows
        private_address = module.windows_admin_vm.network_interfaces["primary"].private_ip_address
      }
    }
    application_access = {
      bastion_name           = local.names.bastion
      cyclecloud_private_url = "https://${local.names.cyclecloud}.${local.private_dns_zones.cyclecloud}"
    }
    key_vault_private_name = "${local.names.key_vault}.${local.private_dns_zones.key_vault}"
    versions = {
      cyclecloud          = local.cyclecloud_version
      scheduler_image     = local.scheduler_image_urn
      burst_compute_image = local.burst_compute_image_urn
      windows_image = join(":", [
        var.windows_image.publisher,
        var.windows_image.offer,
        var.windows_image.sku,
        var.windows_image.version
      ])
    }
    validation = {
      plan_digest           = "record-after-plan-review"
      preflight_digest      = "record-after-plan-review"
      capacity_probe_digest = "record-after-plan-review"
      approval_reference    = "record-after-plan-review"
    }
  }
}

output "cyclecloud_deployment" {
  description = "Secret-free inputs for the separately approved CycleCloud VM-only Bicep deployment stack."
  value = {
    location                           = var.source_region
    resource_group_name                = module.resource_group.name
    vm_name                            = local.names.cyclecloud
    vm_size                            = var.cyclecloud_vm_size
    zone                               = "1"
    nic_resource_id                    = module.cyclecloud_nic.resource_id
    user_assigned_identity_resource_id = module.cyclecloud_control_identity.resource_id
    user_assigned_identity_client_id   = module.cyclecloud_control_identity.client_id
    locker_identity_resource_id        = module.cyclecloud_locker_identity.resource_id
    locker_storage_account_name        = module.cyclecloud_locker_storage.name
    compute_resource_group_name        = module.cyclecloud_compute_resource_group.name
    subscription_id                    = var.subscription_id
    tenant_id                          = var.tenant_id
    burst_region                       = var.burst_region
    key_vault_name                     = local.names.key_vault
    private_name                       = "${local.names.cyclecloud}.${local.private_dns_zones.cyclecloud}"
    cyclecloud_admin_username          = var.cyclecloud_admin_username
    custom_data                        = local.cyclecloud_custom_data
    image                              = var.cyclecloud_image
    tags                               = local.common_tags
  }
}
