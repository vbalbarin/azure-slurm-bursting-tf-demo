output "inventory" {
  description = "Secret-free private environment inventory."
  value = {
    environment_name = var.environment_name
    source_region    = var.source_region
    burst_region     = var.burst_region
    cluster_name     = var.cluster_name
    private_hosts = {
      cyclecloud = {
        name            = local.names.cyclecloud
        private_address = module.cyclecloud_vm.network_interfaces["primary"].private_ip_address
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
      cyclecloud = local.cyclecloud_version
      scheduler_image = join(":", [
        var.scheduler_image.publisher,
        var.scheduler_image.offer,
        var.scheduler_image.sku,
        var.scheduler_image.version
      ])
      windows_image = join(":", [
        var.windows_image.publisher,
        var.windows_image.offer,
        var.windows_image.sku,
        var.windows_image.version
      ])
    }
    validation = {
      plan_digest        = "record-after-plan-review"
      approval_reference = "record-after-plan-review"
    }
  }
}

output "credential_secret_references" {
  description = "Key Vault references for generated VM credentials."
  value = {
    cyclecloud = module.cyclecloud_vm.admin_ssh_keys
    scheduler  = module.scheduler_vm.admin_ssh_keys
    windows    = module.windows_admin_vm.admin_password
  }
  sensitive = true
}
