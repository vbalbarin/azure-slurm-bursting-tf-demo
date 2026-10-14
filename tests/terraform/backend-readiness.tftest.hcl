mock_provider "azurerm" {}
mock_provider "azapi" {}

variables {
  subscription_id            = "00000000-0000-0000-0000-000000000000"
  tenant_id                  = "00000000-0000-0000-0000-000000000000"
  environment_name           = "demo"
  source_region              = "eastus"
  burst_region               = "southcentralus"
  burst_zone                 = "1"
  alternate_burst_placements = [{ region = "eastus2", zone = "1" }]
  source_vnet_cidr           = "10.10.0.0/16"
  burst_vnet_cidr            = "10.20.0.0/16"
  operator_group_object_ids  = ["00000000-0000-0000-0000-000000000000"]
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
  cyclecloud_certificate_secret_id = "https://example.invalid/secrets/tls/version"
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

run "valid_ready_fixture" {
  command = plan
}

run "missing_evidence_rejected" {
  command = plan
  variables {
    backend_readiness_json = null
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "malformed_evidence_rejected" {
  command = plan
  variables {
    backend_readiness_json = "{}"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "wrong_commit_rejected" {
  command = plan
  variables {
    deployment_source_commit = "1111111111111111111111111111111111111111"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "wrong_environment_rejected" {
  command = plan
  variables {
    environment_name = "prod"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "wrong_identity_rejected" {
  command = plan
  variables {
    deployment_principal_id = "22222222-2222-4222-8222-222222222222"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "wrong_coordinates_rejected" {
  command = plan
  variables {
    backend_storage_account_name = "stanotheraccount"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}

run "wrong_execution_context_rejected" {
  command = plan
  variables {
    current_execution_context_digest = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  }
  expect_failures = [terraform_data.backend_readiness_gate]
}
