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
  readiness_phase           = "final"
  readiness_identity = {
    tenant_id      = "22222222-2222-4222-8222-222222222222"
    principal_id   = "44444444-4444-4444-8444-444444444444"
    principal_type = "User"
  }
  readiness_assertions = {
    schema_version          = "1.0"
    source_commit           = "0000000000000000000000000000000000000000"
    coordinates_digest      = "6ca368761f118c234d0c05776a6835d11065251f3f0a3d643f455eebea5f0b7c"
    assessment_started_at   = timeadd(timestamp(), "-1m")
    assessment_completed_at = timestamp()
    execution_context = {
      network_mode                 = "restricted_public"
      runner_context_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      observed_public_source_ipv4  = "203.0.113.10"
      resolved_blob_ipv4_addresses = ["20.1.2.3"]
      observed_at                  = timestamp()
    }
    checks = {
      account_context      = { command_id = "az_account_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "tenant-and-subscription-match" }
      backend_exists       = { command_id = "az_storage_account_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "account-exists" }
      container_exists     = { command_id = "az_storage_container_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "tfstate" }
      dns                  = { command_id = "getent_blob_endpoint", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "20.1.2.3" }
      network              = { command_id = "curl_blob_endpoint", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "reachable" }
      authorization        = { command_id = "az_storage_blob_list", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "authorized" }
      state_key_separation = { command_id = "terraform_coordinate_check", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "three-distinct-keys" }
      migration            = { command_id = "terraform_state_pull", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "lineage-and-count-match" }
      locking              = { command_id = "terraform_lock_conflict", observed_at = timestamp(), exit_code = 1, status = "passed", observed_value = "second-operation-blocked" }
    }
  }
}

run "final_readiness_all_checks_pass" {
  command = apply

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
    condition     = output.backend_readiness.status == "ready" && output.backend_readiness.failure_class == "none"
    error_message = "Fresh, bound, all-passed final assertions must produce ready evidence."
  }

  assert {
    condition     = output.backend_readiness.execution_context.runner_context_digest == "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    error_message = "Readiness must remain bound to the assessed runner context."
  }

  assert {
    condition = local.readiness_failure_classes == {
      account_context      = "authentication_failed"
      backend_exists       = "missing_backend"
      container_exists     = "missing_container"
      dns                  = "dns_failed"
      network              = "network_failed"
      authorization        = "authorization_failed"
      state_key_separation = "state_key_collision"
      migration            = "configuration_mismatch"
      locking              = "lock_failed"
    }
    error_message = "Every stable readiness failure class must retain its documented check mapping."
  }
}

run "preliminary_readiness_allows_only_unrun_migration_and_locking" {
  command = apply

  variables {
    readiness_phase = "preliminary"
    readiness_assertions = {
      schema_version          = "1.0"
      source_commit           = "0000000000000000000000000000000000000000"
      coordinates_digest      = "6ca368761f118c234d0c05776a6835d11065251f3f0a3d643f455eebea5f0b7c"
      assessment_started_at   = timeadd(timestamp(), "-1m")
      assessment_completed_at = timestamp()
      execution_context = {
        network_mode                 = "restricted_public"
        runner_context_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        observed_public_source_ipv4  = "203.0.113.10"
        resolved_blob_ipv4_addresses = ["20.1.2.3"]
        observed_at                  = timestamp()
      }
      checks = {
        account_context      = { command_id = "az_account_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "tenant-and-subscription-match" }
        backend_exists       = { command_id = "az_storage_account_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "account-exists" }
        container_exists     = { command_id = "az_storage_container_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "tfstate" }
        dns                  = { command_id = "getent_blob_endpoint", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "20.1.2.3" }
        network              = { command_id = "curl_blob_endpoint", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "reachable" }
        authorization        = { command_id = "az_storage_blob_list", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "authorized-after-role-propagation" }
        state_key_separation = { command_id = "terraform_coordinate_check", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "three-distinct-keys" }
        migration            = { command_id = "terraform_state_pull", observed_at = timestamp(), exit_code = null, status = "not_run", observed_value = "" }
        locking              = { command_id = "terraform_lock_conflict", observed_at = timestamp(), exit_code = null, status = "not_run", observed_value = "" }
      }
    }
  }

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
    condition     = local.readiness_valid && output.backend_readiness.status == "failed" && output.backend_readiness.checks.migration.status == "not_run" && output.backend_readiness.checks.locking.status == "not_run"
    error_message = "Preliminary assertions must be valid with only migration and locking not_run while remaining ineligible as final ready evidence."
  }
}

run "missing_backend_classified" {
  command = apply

  variables {
    readiness_assertions = {
      schema_version          = "1.0"
      source_commit           = "0000000000000000000000000000000000000000"
      coordinates_digest      = "6ca368761f118c234d0c05776a6835d11065251f3f0a3d643f455eebea5f0b7c"
      assessment_started_at   = timeadd(timestamp(), "-1m")
      assessment_completed_at = timestamp()
      execution_context = {
        network_mode                 = "restricted_public"
        runner_context_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        observed_public_source_ipv4  = "203.0.113.10"
        resolved_blob_ipv4_addresses = ["20.1.2.3"]
        observed_at                  = timestamp()
      }
      checks = {
        account_context      = { command_id = "az_account_show", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "tenant-and-subscription-match" }
        backend_exists       = { command_id = "az_storage_account_show", observed_at = timestamp(), exit_code = 3, status = "failed", observed_value = "not-found" }
        container_exists     = { command_id = "az_storage_container_show", observed_at = timestamp(), exit_code = 3, status = "failed", observed_value = "not-found" }
        dns                  = { command_id = "getent_blob_endpoint", observed_at = timestamp(), exit_code = 2, status = "failed", observed_value = "not-resolved" }
        network              = { command_id = "curl_blob_endpoint", observed_at = timestamp(), exit_code = 6, status = "failed", observed_value = "unreachable" }
        authorization        = { command_id = "az_storage_blob_list", observed_at = timestamp(), exit_code = 3, status = "failed", observed_value = "not-run-after-missing-account" }
        state_key_separation = { command_id = "terraform_coordinate_check", observed_at = timestamp(), exit_code = 0, status = "passed", observed_value = "three-distinct-keys" }
        migration            = { command_id = "terraform_state_pull", observed_at = timestamp(), exit_code = 1, status = "failed", observed_value = "state-unavailable" }
        locking              = { command_id = "terraform_lock_conflict", observed_at = timestamp(), exit_code = 1, status = "failed", observed_value = "lock-unavailable" }
      }
    }
  }

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
    condition     = output.backend_readiness.status == "failed" && output.backend_readiness.failure_class == "missing_backend"
    error_message = "A failed account lookup must classify as missing_backend."
  }
}
