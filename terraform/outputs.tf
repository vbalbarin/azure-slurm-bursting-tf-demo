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
    location                       = var.source_region
    resource_group_name            = module.resource_group.name
    vm_name                        = local.names.cyclecloud
    vm_size                        = var.cyclecloud_vm_size
    zone                           = "1"
    nic_resource_id                = module.cyclecloud_nic.resource_id
    vm_resource_id                 = local.cyclecloud_vm_resource_id
    locker_identity_resource_id    = module.cyclecloud_locker_identity.resource_id
    locker_storage_account_name    = module.cyclecloud_locker_storage.name
    compute_resource_group_name    = module.cyclecloud_compute_resource_group.name
    subscription_id                = var.subscription_id
    tenant_id                      = var.tenant_id
    source_revision                = jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).sourceRevision
    burst_region                   = var.burst_region
    key_vault_name                 = local.names.key_vault
    private_name                   = "${local.names.cyclecloud}.${local.private_dns_zones.cyclecloud}"
    cyclecloud_admin_username      = var.cyclecloud_admin_username
    custom_data                    = local.cyclecloud_custom_data
    chef_payload_base64            = local.chef_role_payloads.cyclecloud.policy_archive_base64
    chef_manifest_base64           = local.cyclecloud_chef_manifest_base64
    chef_node_specification_base64 = local.cyclecloud_chef_specification_base64
    chef_policy_lock_base64        = local.cyclecloud_chef_lock_base64
    chef_payload_sha256            = jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).artifacts[index(jsondecode(local.chef_role_payloads.cyclecloud.manifest_json).artifacts[*].kind, "policy")].sha256
    chef_manifest_sha256           = sha256(local.chef_role_payloads.cyclecloud.manifest_json)
    chef_node_specification_sha256 = sha256(local.cyclecloud_chef_specification_json)
    chef_policy_lock_sha256        = filesha256(local.cyclecloud_chef_lock_path)
    chef_decoded_size_bytes        = local.cyclecloud_chef_decoded_size
    image                          = var.cyclecloud_image
    tags                           = local.common_tags
  }
}

output "cyclecloud_identity_rbac" {
  description = "Value-free CycleCloud system-identity lifecycle and approved RBAC contract."
  value = {
    phase                         = var.cyclecloud_identity_phase
    vm_resource_id                = local.cyclecloud_vm_resource_id
    system_principal_id           = local.cyclecloud_system_principal_id
    custom_role_definition_id     = azurerm_role_definition.cyclecloud_orchestrator.role_definition_resource_id
    custom_role_definition_digest = local.cyclecloud_custom_role_definition_digest
    custom_role_assignment_scope  = local.cyclecloud_subscription_scope
    key_vault_assignment_scope    = module.key_vault.resource_id
    locker_identity_resource_id   = module.cyclecloud_locker_identity.resource_id
    locker_role                   = "Storage Blob Data Reader"
    locker_assignment_scope       = module.cyclecloud_locker_storage.resource_id
    post_create_rbac_enabled      = local.cyclecloud_post_create_rbac
  }
}

output "scheduler_bootstrap" {
  description = "Secret-free scheduler bundle, specification, identity, and governed-dispatch references."
  value = {
    role                    = "scheduler"
    source_revision         = jsondecode(local.chef_role_payloads.scheduler.manifest_json).sourceRevision
    policy_revision         = jsondecode(local.chef_role_payloads.scheduler.manifest_json).policyRevision
    policy_lock_sha256      = jsondecode(local.chef_role_payloads.scheduler.manifest_json).policyLockSha256
    manifest_digest         = jsondecode(local.chef_role_payloads.scheduler.manifest_json).manifestDigest
    specification           = local.chef_node_specifications.scheduler
    specification_digest    = local.chef_node_specifications.scheduler.specificationDigest
    identity_resource_id    = module.scheduler_identity.resource_id
    identity_client_id      = module.scheduler_identity.client_id
    key_vault_role          = local.scheduler_key_vault_role
    custom_data_sha256      = sha256(base64decode(local.scheduler_custom_data))
    custom_data_size_bytes  = length(base64decode(local.scheduler_custom_data))
    convergence_entry_point = "/opt/slurm-demo/current/chef/bin/converge-scheduler.sh"
    dependency_receipts = {
      cyclecloud_convergence = "/var/lib/slurm-demo/receipts/cyclecloud.json"
      scheduler_environment  = "/var/lib/slurm-demo/scheduler/state.json"
      secret_access          = "/var/lib/slurm-demo/receipts/secret-access.json"
      hpc_user               = "/var/lib/slurm-demo/receipts/hpc-user-gate.json"
    }
    public_identity_receipt = "/var/lib/slurm-demo/scheduler/hpcuser01-public-identity.json"
  }
}
