locals {
  backend_expected_check_keys = toset([
    "account_context",
    "backend_exists",
    "container_exists",
    "dns",
    "network",
    "authorization",
    "state_key_separation",
    "migration",
    "locking",
  ])
  backend_readiness_raw = (
    var.backend_readiness_json != null
    ? var.backend_readiness_json
    : try(file(var.backend_readiness_file), null)
  )
  backend_readiness            = try(jsondecode(local.backend_readiness_raw), null)
  backend_readiness_check_keys = toset(keys(try(local.backend_readiness.checks, {})))
  backend_readiness_checks_pass = (
    local.backend_readiness != null &&
    length(setsubtract(local.backend_expected_check_keys, local.backend_readiness_check_keys)) == 0 &&
    length(setsubtract(local.backend_readiness_check_keys, local.backend_expected_check_keys)) == 0 &&
    alltrue([
      for check in values(try(local.backend_readiness.checks, {})) :
      try(check.status, "failed") == "passed"
    ])
  )
  backend_readiness_valid = (
    local.backend_readiness != null &&
    var.deployment_source_commit != null &&
    var.deployment_principal_id != null &&
    var.current_execution_context_digest != null &&
    var.backend_storage_account_name != null &&
    try(local.backend_readiness.status, "failed") == "ready" &&
    try(local.backend_readiness.failure_class, "configuration_mismatch") == "none" &&
    try(local.backend_readiness.source_commit, "") == var.deployment_source_commit &&
    try(local.backend_readiness.identity.tenant_id, "") == var.tenant_id &&
    try(local.backend_readiness.identity.principal_id, "") == var.deployment_principal_id &&
    try(local.backend_readiness.coordinates.subscription_id, "") == var.subscription_id &&
    try(local.backend_readiness.coordinates.tenant_id, "") == var.tenant_id &&
    try(local.backend_readiness.coordinates.storage_account_name, "") == var.backend_storage_account_name &&
    try(local.backend_readiness.coordinates.container_name, "") == var.backend_container_name &&
    try(local.backend_readiness.execution_context.runner_context_digest, "") == var.current_execution_context_digest &&
    try(local.backend_readiness.coordinates.state_keys.main, "") == "${var.backend_environment_name}/main.tfstate" &&
    try(local.backend_readiness.coordinates.state_keys.capacity_probe, "") == "${var.backend_environment_name}/capacity-probe.tfstate" &&
    try(local.backend_readiness.coordinates.state_keys.bootstrap, "") == "${var.backend_environment_name}/bootstrap.tfstate" &&
    length(distinct(values(try(local.backend_readiness.coordinates.state_keys, {})))) == 3 &&
    try(timecmp(plantimestamp(), local.backend_readiness.assessed_at), -1) >= 0 &&
    try(timecmp(plantimestamp(), timeadd(local.backend_readiness.assessed_at, "1h")), 1) <= 0 &&
    local.backend_readiness_checks_pass
  )
}

resource "terraform_data" "backend_readiness_gate" {
  input = {
    readiness_digest = try(sha256(local.backend_readiness_raw), null)
  }

  lifecycle {
    precondition {
      condition     = local.backend_readiness_valid
      error_message = "Current schema-valid backend readiness evidence matching source, identity, coordinates, execution context, migration, and locking is required before planning."
    }
  }
}
