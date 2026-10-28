locals {
  resource_group_name                    = "rg-${var.environment_name}-slurm"
  cyclecloud_compute_resource_group_name = "rg-${var.environment_name}-cyclecloud-compute"
  cyclecloud_version                     = "8.9.3"
  scheduler_image_urn = join(":", [
    var.scheduler_image.publisher,
    var.scheduler_image.offer,
    var.scheduler_image.sku,
    var.scheduler_image.version
  ])
  burst_compute_image_urn = join(":", [
    var.burst_compute_image.publisher,
    var.burst_compute_image.offer,
    var.burst_compute_image.sku,
    var.burst_compute_image.version
  ])
  # tflint-ignore: terraform_unused_declarations
  max_burst_nodes = 1
  chef_role_payloads = var.chef_role_payloads != null ? var.chef_role_payloads : {
    for role in ["cyclecloud", "scheduler"] :
    role => {
      policy_archive_base64 = ""
      manifest_json = jsonencode({
        schemaVersion             = 1
        role                      = role
        sourceRevision            = ""
        policyName                = role == "scheduler" ? "slurm" : "cyclecloud"
        policyRevision            = ""
        policyLockSha256          = ""
        policyArchiveBase64Sha256 = sha256("")
        artifacts = [{
          name      = "${role}.tgz"
          kind      = "policy"
          version   = ""
          uri       = null
          sha256    = ""
          sizeBytes = 0
        }]
        manifestDigest = ""
      })
    }
  }

  names = {
    source_vnet        = "vnet-source"
    burst_vnet         = "vnet-burst"
    cyclecloud         = "${var.environment_name}-cyclecloud"
    scheduler          = "${var.environment_name}-scheduler"
    windows            = "${var.environment_name}-admin"
    bastion            = "${var.environment_name}-bastion"
    source_nat         = "${var.environment_name}-source-nat"
    burst_nat          = "${var.environment_name}-burst-nat"
    key_vault          = substr(replace("${var.environment_name}-slurm-kv", "-", ""), 0, 24)
    log_analytics      = "${var.environment_name}-logs"
    scheduler_identity = "${var.environment_name}-scheduler-bootstrap"
    locker_identity    = "${var.environment_name}-cyclecloud-locker"
    locker_storage     = substr("st${replace(var.environment_name, "-", "")}cc${substr(md5(var.subscription_id), 0, 8)}", 0, 24)
  }

  source_subnets = {
    management = cidrsubnet(var.source_vnet_cidr, 4, 0)
    access     = cidrsubnet(var.source_vnet_cidr, 4, 1)
    private    = cidrsubnet(var.source_vnet_cidr, 4, 2)
    bastion    = cidrsubnet(var.source_vnet_cidr, 4, 3)
  }

  burst_subnets = {
    compute = cidrsubnet(var.burst_vnet_cidr, 4, 0)
  }

  private_dns_zones = {
    key_vault  = "privatelink.vaultcore.azure.net"
    cyclecloud = "cyclecloud.internal"
    blob       = "privatelink.blob.core.windows.net"
  }

  # tflint-ignore: terraform_unused_declarations
  approved_flows = {
    bastion_ssh      = { protocol = "Tcp", port = 22 }
    bastion_rdp      = { protocol = "Tcp", port = 3389 }
    cyclecloud_https = { protocol = "Tcp", port = 443 }
    cyclecloud_api   = { protocol = "Tcp", port = 9443 }
    nfs              = { protocol = "Tcp", port = 2049 }
    slurm_controller = { protocol = "Tcp", port = 6817 }
    slurm_compute    = { protocol = "Tcp", port = 6818 }
  }

  common_tags = {
    environment = var.environment_name
    workload    = "slurm-bursting-demo"
    managed_by  = "terraform"
    source      = "azure-verified-modules"
  }

  key_vault_tags = merge(
    local.common_tags,
    var.key_vault_provisioning_access_enabled ? {
      SecurityControl = "Ignore"
    } : {}
  )

  scheduler_private_address = cidrhost(local.source_subnets.management, 10)
  scheduler_key_vault_role  = "Key Vault Secrets User"
  cyclecloud_admin_secret_name = join("-", [
    "cyclecloud",
    "admin",
    "password",
  ])

  chef_node_specification_common = {
    schemaVersion                 = 1
    sourceRevision                = try(jsondecode(local.chef_role_payloads.scheduler.manifest_json).sourceRevision, "")
    environment                   = var.environment_name
    clusterName                   = var.cluster_name
    cyclecloudUrl                 = "https://${local.names.cyclecloud}.${local.private_dns_zones.cyclecloud}"
    sourceRegion                  = var.source_region
    burstRegion                   = var.burst_region
    schedulerPrivateAddress       = local.scheduler_private_address
    schedulerPrivateName          = "${local.names.scheduler}.${local.private_dns_zones.cyclecloud}"
    burstCidr                     = local.burst_subnets.compute
    burstSubnetId                 = "${local.resource_group_name}/${local.names.burst_vnet}/snet-compute"
    burstZone                     = var.burst_zone
    burstVmSize                   = var.burst_vm_size
    burstImageName                = "almalinux9"
    lockerIdentityResourceId      = "/subscriptions/${var.subscription_id}/resourceGroups/${local.resource_group_name}/providers/Microsoft.ManagedIdentity/userAssignedIdentities/${local.names.locker_identity}"
    slurmVersion                  = "26.05.4-1.el9"
    slurmTemplateVersion          = "26.05.4"
    registeredSlurmProjectVersion = "4.0.9"
    slurmIdentity = {
      uid = var.slurm_uid_gid
      gid = var.slurm_uid_gid
    }
    mungeIdentity = {
      uid = var.munge_uid_gid
      gid = var.munge_uid_gid
    }
    hpcUser = {
      name = var.demo_username
      uid  = var.demo_user_uid_gid
      gid  = var.demo_user_uid_gid
      home = var.demo_user_home
    }
    secretReferences = {
      vaultUri                = "https://${local.names.key_vault}.vault.azure.net"
      cyclecloudAdminPassword = local.cyclecloud_admin_secret_name
    }
  }

  chef_node_specifications_without_digest = {
    for role in ["cyclecloud", "scheduler"] :
    role => merge(local.chef_node_specification_common, {
      role           = role
      sourceRevision = try(jsondecode(local.chef_role_payloads[role].manifest_json).sourceRevision, "")
    })
  }

  chef_node_specifications = {
    for role, specification in local.chef_node_specifications_without_digest :
    role => merge(specification, {
      specificationDigest = sha256(jsonencode(specification))
    })
  }
}
