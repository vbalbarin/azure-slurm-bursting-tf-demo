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
  lifecycle_action = "unlock"
  lifecycle_assertions = {
    assessed_at                  = "2026-10-14T13:00:00Z"
    approval_reference           = "approval-unlock-001"
    main_state_status            = "empty"
    main_managed_resource_count  = 0
    probe_state_status           = "empty"
    probe_managed_resource_count = 0
    bootstrap_state_location     = "local"
    bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    reverse_migration_verified   = true
  }
}

run "unlock_ready" {
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
    condition     = output.backend_lifecycle.status == "ready"
    error_message = "A verified unlock action must be ready."
  }

  assert {
    condition     = output.backend_lifecycle.action == "unlock"
    error_message = "Unlock evidence must preserve its explicit action."
  }

  assert {
    condition = (
      local.container_role_assignments.operator_group.principal_id == var.operator_group_object_id &&
      local.container_role_assignments.operator_group.principal_type == "Group" &&
      local.container_role_assignments.operator_group.role_definition_id_or_name == "Storage Blob Data Contributor"
    )
    error_message = "Replacement access must remain group-based and secret-free."
  }
}

run "migrate_local_is_a_distinct_action" {
  command = plan

  variables {
    lifecycle_action = "migrate_local"
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
    condition     = output.backend_lifecycle.status == "ready" && output.backend_lifecycle.action == "migrate_local"
    error_message = "Reverse migration must be represented as a distinct ready lifecycle action."
  }
}

run "destroy_requires_separate_action" {
  command = plan

  variables {
    lifecycle_action = "destroy"
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:05:00Z"
      approval_reference           = "approval-destroy-002"
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = true
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
    condition     = output.backend_lifecycle.action == "destroy" && output.backend_lifecycle.approval_reference == "approval-destroy-002"
    error_message = "Destroy must use its own action and approval reference."
  }
}

run "dependent_state_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "managed"
      main_managed_resource_count  = 1
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = true
    }
  }

  expect_failures = [var.lifecycle_action]
}

run "operate_reports_stable_blocking_class" {
  command = plan

  variables {
    lifecycle_action = "operate"
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "managed"
      main_managed_resource_count  = 1
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = true
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
    condition     = output.backend_lifecycle.status == "blocked" && output.backend_lifecycle.failure_class == "dependent_state_not_empty"
    error_message = "Lifecycle evidence must retain the stable dependent_state_not_empty class."
  }
}

run "capacity_probe_state_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "managed"
      probe_managed_resource_count = 2
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = true
    }
  }

  expect_failures = [var.lifecycle_action]
}

run "missing_local_state_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "missing"
      bootstrap_state_digest       = null
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = false
    }
  }

  expect_failures = [var.lifecycle_action]
}

run "digest_mismatch_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
      reverse_migration_verified   = true
    }
  }

  expect_failures = [var.lifecycle_action]
}

run "reverse_migration_failure_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = "approval-unlock-001"
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "remote"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = false
    }
  }

  expect_failures = [var.lifecycle_action]
}

run "existing_mode_has_no_removal_path" {
  command = plan

  variables {
    ownership_mode           = "existing"
    lifecycle_action         = "unlock"
    operator_group_object_id = null
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
  }

  expect_failures = [var.lifecycle_action]
}

run "missing_approval_blocks_removal" {
  command = plan

  variables {
    lifecycle_assertions = {
      assessed_at                  = "2026-10-14T13:00:00Z"
      approval_reference           = ""
      main_state_status            = "empty"
      main_managed_resource_count  = 0
      probe_state_status           = "empty"
      probe_managed_resource_count = 0
      bootstrap_state_location     = "local"
      bootstrap_state_digest       = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      expected_state_digest        = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
      reverse_migration_verified   = true
    }
  }

  expect_failures = [var.lifecycle_action]
}
