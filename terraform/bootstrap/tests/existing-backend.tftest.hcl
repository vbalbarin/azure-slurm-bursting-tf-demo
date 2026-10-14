mock_provider "azurerm" {
  mock_data "azurerm_storage_account" {
    defaults = {
      id                         = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate"
      min_tls_version            = "TLS1_2"
      https_traffic_only_enabled = true
    }
  }

  mock_data "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate/blobServices/default/containers/tfstate"
    }
  }
}
mock_provider "azapi" {}

variables {
  subscription_id           = "11111111-1111-4111-8111-111111111111"
  tenant_id                 = "22222222-2222-4222-8222-222222222222"
  location                  = "eastus"
  workload_name             = "slurm"
  environment_name          = "demo"
  instance                  = 1
  uniqueness_code           = "a1b2"
  ownership_mode            = "existing"
  network_mode              = "restricted_public"
  allowed_public_ipv4_cidrs = ["203.0.113.10/32"]
  existing_backend = {
    resource_group_name               = "rg-state"
    resource_group_id                 = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state"
    storage_account_name              = "stexistingstate"
    storage_account_id                = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate"
    container_name                    = "tfstate"
    container_id                      = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate/blobServices/default/containers/tfstate"
    public_network_access_enabled     = true
    shared_access_key_enabled         = false
    allow_nested_items_to_be_public   = false
    infrastructure_encryption_enabled = true
    minimum_tls_version               = "TLS1_2"
    https_traffic_only_enabled        = true
  }
  tags          = { environment = "demo", workload = "slurm" }
  source_commit = "0000000000000000000000000000000000000000"
  readiness_identity = {
    tenant_id      = "22222222-2222-4222-8222-222222222222"
    principal_id   = "44444444-4444-4444-8444-444444444444"
    principal_type = "User"
  }
}

run "existing_mode_is_validate_only" {
  command = plan

  override_data {
    target = data.azurerm_storage_account.existing[0]
    values = {
      id                         = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate"
      min_tls_version            = "TLS1_2"
      https_traffic_only_enabled = true
    }
  }

  override_data {
    target = data.azurerm_storage_container.existing[0]
    values = {
      id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-state/providers/Microsoft.Storage/storageAccounts/stexistingstate/blobServices/default/containers/tfstate"
    }
  }

  assert {
    condition     = output.backend_coordinates.ownership_mode == "existing"
    error_message = "Existing mode must preserve validate-only ownership."
  }

  assert {
    condition     = output.backend_coordinates.storage_account_name == "stexistingstate"
    error_message = "Existing coordinates must come from approved inputs."
  }

  assert {
    condition     = length(module.resource_group) == 0 && length(module.storage) == 0
    error_message = "Existing mode must instantiate no resource modules."
  }
}

run "existing_mode_rejects_lifecycle_actions" {
  command = plan

  variables {
    lifecycle_action = "destroy"
  }

  expect_failures = [var.lifecycle_action]
}
