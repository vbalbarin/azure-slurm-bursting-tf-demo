locals {
  linux_bootstrap = base64encode(<<-CLOUD_INIT
    #cloud-config
    package_update: true
    packages:
      - curl
    write_files:
      - path: /usr/local/sbin/chef-policy-bootstrap
        owner: root:root
        permissions: '0700'
        encoding: b64
        content: ${base64encode(file("${path.module}/../chef/bootstrap/linux.sh"))}
    runcmd:
      - [ sh, -c, "echo 'Chef policy convergence requires protected runtime inputs' > /var/log/chef-bootstrap-ready" ]
  CLOUD_INIT
  )
}

module "cyclecloud_nic" {
  source  = "Azure/avm-res-network-networkinterface/azurerm"
  version = "0.1.2"

  location            = var.source_region
  name                = "${local.names.cyclecloud}-nic"
  resource_group_name = module.resource_group.name
  enable_telemetry    = false
  tags                = local.common_tags

  ip_configurations = {
    primary = {
      name                          = "primary"
      subnet_id                     = module.source_vnet.subnets["management"].resource_id
      private_ip_address_allocation = "Dynamic"
      primary                       = true
    }
  }
}

module "scheduler_vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.21.0"

  location            = var.source_region
  name                = local.names.scheduler
  resource_group_name = module.resource_group.name
  os_type             = "Linux"
  sku_size            = var.scheduler_vm_size
  zone                = "1"
  custom_data         = local.linux_bootstrap
  enable_telemetry    = false
  tags                = local.common_tags

  source_image_reference = var.scheduler_image

  account_credentials = {
    admin_credentials = {
      username                           = "scheduleradmin"
      ssh_keys                           = [var.scheduler_admin_ssh_public_key]
      generate_admin_password_or_ssh_key = false
    }
    password_authentication_disabled = true
  }

  managed_identities = {
    system_assigned = true
  }

  network_interfaces = {
    primary = {
      name       = "${local.names.scheduler}-nic"
      is_primary = true
      ip_configurations = {
        primary = {
          name                          = "primary"
          create_public_ip_address      = false
          private_ip_subnet_resource_id = module.source_vnet.subnets["management"].resource_id
          private_ip_address_allocation = "Dynamic"
          is_primary_ipconfiguration    = true
        }
      }
    }
  }
}

module "windows_admin_vm" {
  source  = "Azure/avm-res-compute-virtualmachine/azurerm"
  version = "0.21.0"

  location            = var.source_region
  name                = local.names.windows
  resource_group_name = module.resource_group.name
  os_type             = "Windows"
  sku_size            = var.windows_vm_size
  zone                = "1"
  enable_telemetry    = false
  tags                = local.common_tags

  source_image_reference = var.windows_image
  patch_mode             = "AutomaticByPlatform"
  patch_assessment_mode  = "AutomaticByPlatform"

  account_credentials = {
    admin_credentials = {
      username                           = "windowsadmin"
      password                           = var.windows_admin_password
      generate_admin_password_or_ssh_key = false
    }
  }

  managed_identities = {
    system_assigned = true
  }

  network_interfaces = {
    primary = {
      name       = "${local.names.windows}-nic"
      is_primary = true
      ip_configurations = {
        primary = {
          name                          = "primary"
          create_public_ip_address      = false
          private_ip_subnet_resource_id = module.source_vnet.subnets["access"].resource_id
          private_ip_address_allocation = "Dynamic"
          is_primary_ipconfiguration    = true
        }
      }
    }
  }
}
