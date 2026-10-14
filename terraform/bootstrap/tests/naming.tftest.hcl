mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id           = "11111111-1111-4111-8111-111111111111"
  tenant_id                 = "22222222-2222-4222-8222-222222222222"
  location                  = "eastus"
  workload_name             = "slurm"
  environment_name          = "demo"
  instance                  = 1
  uniqueness_code           = "a1b2"
  operator_group_object_id  = "33333333-3333-4333-8333-333333333333"
  allowed_public_ipv4_cidrs = ["203.0.113.10/32"]
  tags                      = { environment = "demo", workload = "slurm" }
  source_commit             = "0000000000000000000000000000000000000000"
  readiness_identity = {
    tenant_id      = "22222222-2222-4222-8222-222222222222"
    principal_id   = "44444444-4444-4444-8444-444444444444"
    principal_type = "User"
  }
}

run "deterministic_names_and_keys" {
  command = plan

  override_module {
    target = module.resource_group
    outputs = {
      resource_id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-01"
    }
  }

  override_module {
    target = module.storage
    outputs = {
      resource_id       = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-01/providers/Microsoft.Storage/storageAccounts/stslurmdemoeus01a1b2"
      containers        = { state = { id = "/blobServices/default/containers/tfstate" } }
      private_endpoints = {}
    }
  }

  assert {
    condition     = output.backend_coordinates.resource_group_name == "rg-slurm-demo-eus-01"
    error_message = "The resource-group name must follow the approved ALZ pattern."
  }

  assert {
    condition     = output.backend_coordinates.storage_account_name == "stslurmdemoeus01a1b2"
    error_message = "The storage-account name must be deterministic."
  }

  assert {
    condition     = output.backend_coordinates.container_name == "tfstate"
    error_message = "The state container name must remain fixed."
  }

  assert {
    condition = output.backend_coordinates.state_keys == {
      bootstrap      = "demo/bootstrap.tfstate"
      main           = "demo/main.tfstate"
      capacity_probe = "demo/capacity-probe.tfstate"
    }
    error_message = "All state keys must be exact, environment-scoped, and distinct."
  }

  assert {
    condition     = can(regex("^[a-z0-9]{3,24}$", output.backend_coordinates.storage_account_name))
    error_message = "The storage-account name must satisfy Azure naming constraints."
  }
}

run "two_digit_instance" {
  command = plan

  variables {
    instance = 0
  }

  override_module {
    target = module.resource_group
    outputs = {
      resource_id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-00"
    }
  }

  override_module {
    target = module.storage
    outputs = {
      resource_id       = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-00/providers/Microsoft.Storage/storageAccounts/stslurmdemoeus00a1b2"
      containers        = { state = { id = "/blobServices/default/containers/tfstate" } }
      private_endpoints = {}
    }
  }

  assert {
    condition     = output.backend_coordinates.resource_group_name == "rg-slurm-demo-eus-00"
    error_message = "Instances must use a two-digit code."
  }
}

run "invalid_region_rejected" {
  command = plan

  variables {
    location = "moonbase"
  }

  expect_failures = [var.location]
}

run "invalid_uniqueness_rejected" {
  command = plan

  variables {
    uniqueness_code = "ABC"
  }

  expect_failures = [var.uniqueness_code]
}

run "overlength_workload_rejected" {
  command = plan

  variables {
    workload_name = "workloadx"
  }

  expect_failures = [var.workload_name]
}
