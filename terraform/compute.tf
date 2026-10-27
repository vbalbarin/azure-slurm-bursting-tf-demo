locals {
  scheduler_custom_data = base64encode(<<-CLOUD_INIT
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
      - path: /var/lib/slurm-demo/bootstrap/scheduler.tgz
        owner: root:root
        permissions: '0400'
        encoding: b64
        content: ${local.chef_role_payloads.scheduler.policy_archive_base64}
      - path: /var/lib/slurm-demo/bootstrap/scheduler.manifest.json
        owner: root:root
        permissions: '0400'
        encoding: b64
        content: ${base64encode(local.chef_role_payloads.scheduler.manifest_json)}
      - path: /var/lib/slurm-demo/bootstrap/scheduler.node-specification.json
        owner: root:root
        permissions: '0400'
        encoding: b64
        content: ${base64encode(jsonencode(local.chef_node_specifications.scheduler))}
    runcmd:
      - [ install, -d, -m, '0700', /var/lib/slurm-demo/bootstrap ]
      - [ dnf, install, -y, 'https://packages.microsoft.com/config/rhel/9.0/packages-microsoft-prod.rpm' ]
      - [ dnf, install, -y, azure-cli ]
      - [ az, login, --identity, --allow-no-subscriptions, --output, none ]
      - [ az, keyvault, secret, download, --vault-name, '${local.names.key_vault}', --name, chef-license-id, --file, /run/chef-license-id, --encoding, utf-8, --overwrite, --output, none ]
      - [ chmod, '0600', /run/chef-license-id ]
      - [ env, CHEF_POLICY_NAME=slurm, CHEF_MANIFEST_PATH=/var/lib/slurm-demo/bootstrap/scheduler.manifest.json, CHEF_NODE_SPECIFICATION_PATH=/var/lib/slurm-demo/bootstrap/scheduler.node-specification.json, CHEF_POLICY_ARCHIVE_PATH=/var/lib/slurm-demo/bootstrap/scheduler.tgz, CHEF_LICENSE_ID_FILE=/run/chef-license-id, /usr/local/sbin/chef-policy-bootstrap ]
      - [ rm, -f, /run/chef-license-id ]
  CLOUD_INIT
  )
}

resource "terraform_data" "scheduler_bootstrap_contract" {
  input = {
    manifest_digest      = jsondecode(local.chef_role_payloads.scheduler.manifest_json).manifestDigest
    specification_digest = local.chef_node_specifications.scheduler.specificationDigest
  }

  lifecycle {
    precondition {
      condition     = length(base64decode(local.scheduler_custom_data)) <= 60000
      error_message = "Rendered scheduler custom data must not exceed the 60000-byte safety gate."
    }
  }
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
  custom_data         = local.scheduler_custom_data
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
    user_assigned_resource_ids = [module.scheduler_identity.resource_id]
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
          private_ip_address            = local.scheduler_private_address
          private_ip_address_allocation = "Static"
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
resource "terraform_data" "chef_role_payload_gate" {
  input = var.chef_role_payloads != null

  lifecycle {
    precondition {
      condition     = var.chef_role_payloads != null
      error_message = "Approved immutable Chef role payloads are required for an infrastructure plan."
    }
  }
}
