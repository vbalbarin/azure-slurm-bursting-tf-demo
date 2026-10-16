locals {
  name = "${var.environment_name}-capacity-probe"
  tags = {
    purpose    = "slurm-capacity-probe"
    owner      = var.owner
    expires_at = var.expires_at
    temporary  = "true"
  }
}

module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location         = var.burst_region
  name             = "${local.name}-rg"
  enable_telemetry = false
  tags             = local.tags
}

module "network_security_group" {
  source  = "Azure/avm-res-network-networksecuritygroup/azurerm"
  version = "0.6.0"

  location         = var.burst_region
  name             = "${local.name}-nsg"
  parent_id        = module.resource_group.resource_id
  enable_telemetry = false
  tags             = local.tags

  security_rules = {
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

module "virtual_network" {
  source  = "Azure/avm-res-network-virtualnetwork/azurerm"
  version = "0.22.2"

  location         = var.burst_region
  name             = "${local.name}-vnet"
  parent_id        = module.resource_group.resource_id
  address_space    = [var.probe_vnet_cidr]
  enable_telemetry = false
  tags             = local.tags

  subnets = {
    probe = {
      name                            = "snet-probe"
      address_prefix                  = cidrsubnet(var.probe_vnet_cidr, 1, 0)
      default_outbound_access_enabled = false
      network_security_group = {
        id = module.network_security_group.resource_id
      }
    }
  }
}

module "virtual_machine" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.21.0"

  location            = var.burst_region
  zone                = var.burst_zone
  name                = "${local.name}-vm"
  resource_group_name = module.resource_group.name
  os_type             = "Linux"
  sku_size            = var.burst_vm_size
  enable_telemetry    = false
  tags                = local.tags

  source_image_reference = var.burst_compute_image

  plan = {
    name      = var.burst_compute_image.sku
    product   = var.burst_compute_image.offer
    publisher = var.burst_compute_image.publisher
  }

  account_credentials = {
    admin_credentials = {
      username                           = "probeadmin"
      generate_admin_password_or_ssh_key = true
    }
    password_authentication_disabled = true
  }

  network_interfaces = {
    primary = {
      name       = "${local.name}-nic"
      is_primary = true
      ip_configurations = {
        primary = {
          name                          = "primary"
          create_public_ip_address      = false
          private_ip_subnet_resource_id = module.virtual_network.subnets["probe"].resource_id
          private_ip_address_allocation = "Dynamic"
          is_primary_ipconfiguration    = true
        }
      }
    }
  }
}
