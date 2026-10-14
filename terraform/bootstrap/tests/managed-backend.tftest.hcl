mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id             = "11111111-1111-4111-8111-111111111111"
  tenant_id                   = "22222222-2222-4222-8222-222222222222"
  location                    = "eastus"
  workload_name               = "slurm"
  environment_name            = "demo"
  instance                    = 1
  uniqueness_code             = "a1b2"
  operator_group_object_id    = "33333333-3333-4333-8333-333333333333"
  workload_identity_object_id = "55555555-5555-4555-8555-555555555555"
  allowed_public_ipv4_cidrs   = ["203.0.113.10/32"]
  tags                        = { environment = "demo", workload = "slurm" }
  source_commit               = "0000000000000000000000000000000000000000"
  readiness_identity = {
    tenant_id      = "22222222-2222-4222-8222-222222222222"
    principal_id   = "44444444-4444-4444-8444-444444444444"
    principal_type = "User"
  }
}

run "managed_restricted_public_composition" {
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
    condition     = output.backend_coordinates.ownership_mode == "managed"
    error_message = "Managed mode must own the backend."
  }

  assert {
    condition     = output.backend_coordinates.network_mode == "restricted_public"
    error_message = "The default network mode must be restricted public."
  }

  assert {
    condition = local.container_role_assignments == {
      operator_group = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = "33333333-3333-4333-8333-333333333333"
        principal_type             = "Group"
        description                = "Terraform state access for approved operators."
      }
      workload_identity = {
        role_definition_id_or_name = "Storage Blob Data Contributor"
        principal_id               = "55555555-5555-4555-8555-555555555555"
        principal_type             = "ServicePrincipal"
        description                = "Terraform state access for approved automation."
      }
    }
    error_message = "Container-scoped Entra role assignments must cover operators and optional automation."
  }
}

run "unrestricted_public_access_rejected" {
  command = plan

  variables {
    allowed_public_ipv4_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.allowed_public_ipv4_cidrs]
}

run "private_cidr_rejected" {
  command = plan

  variables {
    allowed_public_ipv4_cidrs = ["10.0.0.1/32"]
  }

  expect_failures = [var.allowed_public_ipv4_cidrs]
}
