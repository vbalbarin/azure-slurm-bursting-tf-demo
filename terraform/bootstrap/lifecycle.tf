locals {
  backend_lifecycle = {
    schema_version = "1.0"
    source_commit  = var.source_commit
    assessed_at    = try(var.lifecycle_assertions.assessed_at, "1970-01-01T00:00:00Z")
    status         = local.lifecycle_ready ? "ready" : "blocked"
    failure_class  = local.lifecycle_ready ? "none" : local.lifecycle_failure_class
    ownership_mode = var.ownership_mode
    action         = var.lifecycle_action == "operate" ? "migrate_local" : var.lifecycle_action
    coordinates    = local.backend_coordinates
    namespaces = {
      main = {
        state_status           = try(var.lifecycle_assertions.main_state_status, "unreadable")
        managed_resource_count = try(var.lifecycle_assertions.main_managed_resource_count, 0)
      }
      capacity_probe = {
        state_status           = try(var.lifecycle_assertions.probe_state_status, "unreadable")
        managed_resource_count = try(var.lifecycle_assertions.probe_managed_resource_count, 0)
      }
    }
    bootstrap_state = {
      location                   = try(var.lifecycle_assertions.bootstrap_state_location, "missing")
      digest                     = try(var.lifecycle_assertions.bootstrap_state_digest, null)
      expected_digest            = try(var.lifecycle_assertions.expected_state_digest, null)
      removal_path               = try(var.lifecycle_assertions.removal_path, "acceptance")
      migration_status           = try(var.lifecycle_assertions.state_migration_status, "reverse_migrated")
      reverse_migration_verified = try(var.lifecycle_assertions.reverse_migration_verified, false)
    }
    approval_reference = try(var.lifecycle_assertions.approval_reference, "not-approved")
  }
}
