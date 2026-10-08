module "source_nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.6.0"

  location         = var.source_region
  name             = "${var.environment_name}-source-nsg"
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.common_tags

  security_rules = {
    bastion_ssh = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowBastionSsh"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = local.source_subnets.bastion
      source_port_range          = "*"
      destination_address_prefix = local.source_subnets.management
      destination_port_range     = "22"
    }
    bastion_rdp = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowBastionRdp"
      priority                   = 110
      protocol                   = "Tcp"
      source_address_prefix      = local.source_subnets.bastion
      source_port_range          = "*"
      destination_address_prefix = local.source_subnets.management
      destination_port_range     = "3389"
    }
    cyclecloud_https = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowCycleCloudHttps"
      priority                   = 120
      protocol                   = "Tcp"
      source_address_prefix      = local.source_subnets.management
      source_port_range          = "*"
      destination_address_prefix = local.source_subnets.management
      destination_port_ranges    = ["443", "9443"]
    }
    burst_nfs = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowBurstNfs"
      priority                   = 130
      protocol                   = "Tcp"
      source_address_prefix      = var.burst_vnet_cidr
      source_port_range          = "*"
      destination_address_prefix = local.source_subnets.management
      destination_port_range     = "2049"
    }
    burst_slurm = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowBurstSlurm"
      priority                   = 140
      protocol                   = "Tcp"
      source_address_prefix      = var.burst_vnet_cidr
      source_port_range          = "*"
      destination_address_prefix = local.source_subnets.management
      destination_port_ranges    = ["6817", "6818"]
    }
    deny_all = {
      access                     = "Deny"
      direction                  = "Inbound"
      name                       = "DenyAllInbound"
      priority                   = 4096
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "*"
    }
  }
}

module "burst_nsg" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.6.0"

  location         = var.burst_region
  name             = "${var.environment_name}-burst-nsg"
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.common_tags

  security_rules = {
    scheduler_slurm = {
      access                     = "Allow"
      direction                  = "Inbound"
      name                       = "AllowSchedulerSlurm"
      priority                   = 100
      protocol                   = "Tcp"
      source_address_prefix      = local.source_subnets.management
      source_port_range          = "*"
      destination_address_prefix = local.burst_subnets.compute
      destination_port_ranges    = ["6817", "6818"]
    }
    deny_all = {
      access                     = "Deny"
      direction                  = "Inbound"
      name                       = "DenyAllInbound"
      priority                   = 4096
      protocol                   = "*"
      source_address_prefix      = "*"
      source_port_range          = "*"
      destination_address_prefix = "*"
      destination_port_range     = "*"
    }
  }
}

module "burst_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  location         = var.burst_region
  name             = local.names.burst_vnet
  parent_id        = module.resource_group.resource_id
  address_space    = [var.burst_vnet_cidr]
  enable_telemetry = false
  tags             = local.common_tags

  subnets = {
    compute = {
      name                            = "snet-compute"
      address_prefix                  = local.burst_subnets.compute
      default_outbound_access_enabled = false
      network_security_group = {
        id = module.burst_nsg.resource_id
      }
    }
  }
}

module "source_vnet" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  location         = var.source_region
  name             = local.names.source_vnet
  parent_id        = module.resource_group.resource_id
  address_space    = [var.source_vnet_cidr]
  enable_telemetry = false
  tags             = local.common_tags

  subnets = {
    management = {
      name                            = "snet-management"
      address_prefix                  = local.source_subnets.management
      default_outbound_access_enabled = false
      network_security_group = {
        id = module.source_nsg.resource_id
      }
    }
    access = {
      name                            = "snet-access"
      address_prefix                  = local.source_subnets.access
      default_outbound_access_enabled = false
      network_security_group = {
        id = module.source_nsg.resource_id
      }
    }
    private_endpoint = {
      name                                      = "snet-private-endpoint"
      address_prefix                            = local.source_subnets.private
      private_endpoint_network_policies_enabled = false
      default_outbound_access_enabled           = false
    }
    bastion = {
      name                            = "AzureBastionSubnet"
      address_prefix                  = local.source_subnets.bastion
      default_outbound_access_enabled = false
    }
  }

  peerings = {
    burst = {
      name                                 = "source-to-burst"
      remote_virtual_network_resource_id   = module.burst_vnet.resource_id
      allow_virtual_network_access         = true
      allow_forwarded_traffic              = false
      create_reverse_peering               = true
      reverse_name                         = "burst-to-source"
      reverse_allow_virtual_network_access = true
      reverse_allow_forwarded_traffic      = false
    }
  }
}
