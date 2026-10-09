mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id = "00000000-0000-0000-0000-000000000000"
  tenant_id       = "00000000-0000-0000-0000-000000000000"
  environment_name = "demo"
  source_region    = "eastus"
  burst_region     = "southcentralus"
  source_vnet_cidr = "10.10.0.0/16"
  burst_vnet_cidr  = "10.20.0.0/16"
  operator_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
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
    version   = "latest"
  }
  cyclecloud_vm_size = "Standard_D4s_v6"
  scheduler_vm_size  = "Standard_D4s_v6"
  windows_vm_size    = "Standard_D2s_v6"
  burst_vm_size      = "Standard_HB120rs_v3"
  cluster_name       = "demo-cluster"
  cyclecloud_certificate_secret_id = "https://example.invalid/secrets/tls/version"
  chef_policy_archive_uri = "https://example.invalid/policies"
}

run "cross_region_topology" {
  command = plan

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
    condition     = output.inventory.versions.scheduler_image == "almalinux:almalinux-x86_64:9-gen2:9.8.2026100501"
    error_message = "Inventory must record the persistent scheduler image by role."
  }

  assert {
    condition     = output.inventory.versions.burst_compute_image == "almalinux:almalinux-hpc:9-hpc-gen2:9.8.202608110"
    error_message = "Inventory must record the independently pinned burst-compute image."
  }
}
