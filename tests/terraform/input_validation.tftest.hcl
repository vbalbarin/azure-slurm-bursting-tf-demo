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

run "reject_invalid_burst_zone" {
  command = plan
  variables {
    burst_zone = "4"
  }
  expect_failures = [var.burst_zone]
}

run "reject_selected_placement_as_alternate" {
  command = plan
  variables {
    alternate_burst_placements = [{ region = "southcentralus", zone = "1" }]
  }
  expect_failures = [var.alternate_burst_placements]
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

run "reject_unpinned_scheduler_image" {
  command = plan
  variables {
    scheduler_image = {
      publisher = "almalinux"
      offer     = "almalinux-x86_64"
      sku       = "9-gen2"
      version   = "latest"
    }
  }
  expect_failures = [var.scheduler_image]
}

run "reject_non_hpc_burst_image" {
  command = plan
  variables {
    burst_compute_image = {
      publisher = "almalinux"
      offer     = "almalinux-x86_64"
      sku       = "9-gen2"
      version   = "9.8.2026100501"
    }
  }
  expect_failures = [var.burst_compute_image]
}

run "reject_unpinned_windows_image" {
  command = plan
  variables {
    windows_image = {
      publisher = "MicrosoftWindowsServer"
      offer     = "WindowsServer"
      sku       = "2025-datacenter-azure-edition"
      version   = "latest"
    }
  }
  expect_failures = [var.windows_image]
}
