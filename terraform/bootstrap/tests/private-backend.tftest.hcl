mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id            = "11111111-1111-4111-8111-111111111111"
  tenant_id                  = "22222222-2222-4222-8222-222222222222"
  location                   = "eastus"
  workload_name              = "slurm"
  environment_name           = "demo"
  instance                   = 1
  uniqueness_code            = "a1b2"
  operator_group_object_id   = "33333333-3333-4333-8333-333333333333"
  network_mode               = "private"
  private_endpoint_subnet_id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-runner/subnets/snet-private-endpoints"
  private_dns_zone_id        = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-network/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  tags                       = { environment = "demo", workload = "slurm" }
  source_commit              = "0000000000000000000000000000000000000000"
  readiness_identity = {
    tenant_id      = "22222222-2222-4222-8222-222222222222"
    principal_id   = "44444444-4444-4444-8444-444444444444"
    principal_type = "User"
  }
}

run "managed_private_coordinates" {
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
      resource_id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-01/providers/Microsoft.Storage/storageAccounts/stslurmdemoeus01a1b2"
      containers  = { state = { id = "/blobServices/default/containers/tfstate" } }
      private_endpoints = {
        blob = {
          id = "/subscriptions/11111111-1111-4111-8111-111111111111/resourceGroups/rg-slurm-demo-eus-01/providers/Microsoft.Network/privateEndpoints/pep-slurm-demo-eus-01-blob"
        }
      }
    }
  }

  assert {
    condition     = output.backend_coordinates.network_mode == "private"
    error_message = "Private mode must be represented in coordinates."
  }

  assert {
    condition     = output.backend_coordinates.resource_ids.private_endpoint != null
    error_message = "Managed private mode must expose the embedded private-endpoint resource ID."
  }
}

run "private_mode_rejects_public_cidrs" {
  command = plan

  variables {
    allowed_public_ipv4_cidrs = ["203.0.113.10/32"]
  }

  expect_failures = [var.allowed_public_ipv4_cidrs]
}

run "private_mode_requires_subnet" {
  command = plan

  variables {
    private_endpoint_subnet_id = null
  }

  expect_failures = [var.private_endpoint_subnet_id]
}

run "private_mode_requires_blob_dns_zone" {
  command = plan

  variables {
    private_dns_zone_id = null
  }

  expect_failures = [var.private_dns_zone_id]
}
