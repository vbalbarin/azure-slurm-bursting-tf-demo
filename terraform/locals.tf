locals {
  resource_group_name = "rg-${var.environment_name}-slurm"
  cyclecloud_version  = "8.9.3"
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

  names = {
    source_vnet   = "vnet-source"
    burst_vnet    = "vnet-burst"
    cyclecloud    = "${var.environment_name}-cyclecloud"
    scheduler     = "${var.environment_name}-scheduler"
    windows       = "${var.environment_name}-admin"
    bastion       = "${var.environment_name}-bastion"
    key_vault     = substr(replace("${var.environment_name}-slurm-kv", "-", ""), 0, 24)
    log_analytics = "${var.environment_name}-logs"
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
}
