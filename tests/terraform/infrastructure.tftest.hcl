mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
  environment_name           = "demo"
  backend_environment_name   = "demo"
  source_region              = "eastus"
  burst_region               = "southcentralus"
  burst_zone                 = "1"
  alternate_burst_placements = [{ region = "eastus2", zone = "1" }]
  source_vnet_cidr           = "10.10.0.0/16"
  burst_vnet_cidr            = "10.20.0.0/16"
  operator_group_object_ids  = ["00000000-0000-0000-0000-000000000000"]
  scheduler_admin_ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILOZsLp0yT/oTDgPzOJBUK5vYbmOFwQKcXkyJbYcYlMe test"
  windows_admin_password          = "Valid-Test-Password-123!"
  cyclecloud_image = {
    publisher = "azurecyclecloud"
    offer     = "azure-cyclecloud"
    sku       = "cyclecloud8-gen2"
    version   = "8.9.320260827"
    plan_name = "cyclecloud8-gen2"
    product   = "azure-cyclecloud"
  }
  scheduler_image = {
    publisher = "almalinux"
    offer     = "almalinux-x86_64"
    sku       = "9-gen2"
    version   = "9.8.2026100501"
  }
  burst_compute_image = {
    publisher = "almalinux"
    offer     = "almalinux-hpc"
    sku       = "9-hpc-gen2"
    version   = "9.8.202608110"
  }
  windows_image = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "26100.33438.260905"
  }
  cyclecloud_vm_size               = "Standard_D4s_v6"
  scheduler_vm_size                = "Standard_D4s_v6"
  windows_vm_size                  = "Standard_D2s_v6"
  burst_vm_size                    = "Standard_HB120rs_v3"
  cluster_name                     = "demo-cluster"
  chef_policy_archive_uri          = "https://example.invalid/policies"
  deployment_source_commit         = "0000000000000000000000000000000000000000"
  deployment_principal_id          = "11111111-1111-4111-8111-111111111111"
  backend_storage_account_name     = "stslurmdemoeus01a1b2"
  current_execution_context_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  backend_readiness_json = jsonencode({
    source_commit = "0000000000000000000000000000000000000000"
    assessed_at   = timestamp()
    status        = "ready"
    failure_class = "none"
    identity = {
      tenant_id    = "00000000-0000-0000-0000-000000000000"
      principal_id = "11111111-1111-4111-8111-111111111111"
    }
    execution_context = {
      runner_context_digest = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    }
    coordinates = {
      subscription_id      = "00000000-0000-0000-0000-000000000000"
      tenant_id            = "00000000-0000-0000-0000-000000000000"
      storage_account_name = "stslurmdemoeus01a1b2"
      container_name       = "tfstate"
      state_keys = {
        bootstrap      = "demo/bootstrap.tfstate"
        main           = "demo/main.tfstate"
        capacity_probe = "demo/capacity-probe.tfstate"
      }
    }
    checks = {
      account_context      = { status = "passed" }
      backend_exists       = { status = "passed" }
      container_exists     = { status = "passed" }
      dns                  = { status = "passed" }
      network              = { status = "passed" }
      authorization        = { status = "passed" }
      state_key_separation = { status = "passed" }
      migration            = { status = "passed" }
      locking              = { status = "passed" }
    }
  })
}

run "cross_region_topology" {
  command = plan

  assert {
    condition     = !contains(keys(local.key_vault_tags), "SecurityControl")
    error_message = "Accepted private-only mode must not retain the temporary Key Vault policy exclusion."
  }

  assert {
    condition     = module.source_vnet.name == "vnet-source"
    error_message = "The source VNET must use the contract name."
  }

  assert {
    condition     = module.burst_vnet.name == "vnet-burst"
    error_message = "The burst VNET must use the contract name."
  }

  assert {
    condition     = local.max_burst_nodes == 1
    error_message = "Acceptance must be capped at one burst node."
  }

  assert {
    condition     = local.names.log_analytics == "demo-logs"
    error_message = "Exactly one named Log Analytics workspace must be composed."
  }

  assert {
    condition     = module.cyclecloud_nic.location == "eastus"
    error_message = "Terraform must own the standalone CycleCloud NIC."
  }

  assert {
    condition     = output.cyclecloud_deployment.image.version == "8.9.320260827"
    error_message = "The Bicep handoff must retain the pinned CycleCloud Marketplace image."
  }

  assert {
    condition     = output.inventory.versions.scheduler_image == "almalinux:almalinux-x86_64:9-gen2:9.8.2026100501"
    error_message = "Inventory must record the persistent scheduler image by role."
  }

  assert {
    condition     = output.inventory.versions.burst_compute_image == "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
    error_message = "Inventory must record the independently pinned burst-compute image."
  }
}

run "key_vault_provisioning_policy_exclusion_is_resource_scoped" {
  command = plan

  variables {
    key_vault_provisioning_access_enabled = true
    key_vault_provisioning_ipv4_cidrs     = ["203.0.113.10/32"]
  }

  assert {
    condition     = local.key_vault_tags.SecurityControl == "Ignore"
    error_message = "Provisioning mode must apply the exact policy exclusion to the Key Vault."
  }

  assert {
    condition     = !contains(keys(local.common_tags), "SecurityControl")
    error_message = "The policy exclusion must not be applied through common or resource-group tags."
  }
}
