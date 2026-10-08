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
    offer     = "almalinux-hpc"
    sku       = "9-gen2"
    version   = "9.5.20250121"
  }
  windows_image = {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2025-datacenter-azure-edition"
    version   = "latest"
  }
  cyclecloud_vm_size = "Standard_D4s_v5"
  scheduler_vm_size  = "Standard_D4s_v5"
  windows_vm_size    = "Standard_D2s_v5"
  burst_vm_size      = "Standard_HB120rs_v3"
  cluster_name       = "demo-cluster"
  cyclecloud_certificate_secret_id = "https://example.invalid/secrets/tls/version"
  chef_policy_archive_uri = "https://example.invalid/policies"
}

run "valid_inputs" {
  command = plan
}

run "reject_identical_regions" {
  command = plan
  variables {
    burst_region = "eastus"
  }
  expect_failures = [var.burst_region]
}

run "reject_overlapping_cidrs" {
  command = plan
  variables {
    burst_vnet_cidr = "10.10.1.0/24"
  }
  expect_failures = [var.burst_vnet_cidr]
}

run "reject_nonpositive_idle_timeout" {
  command = plan
  variables {
    idle_timeout_minutes = 0
  }
  expect_failures = [var.idle_timeout_minutes]
}
