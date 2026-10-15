locals {
  region_codes = {
    centralus      = "cus"
    eastus         = "eus"
    eastus2        = "eu2"
    northcentralus = "ncu"
    southcentralus = "scu"
    westcentralus  = "wcu"
    westus         = "wus"
    westus2        = "wu2"
    westus3        = "wu3"
  }

  region_code         = local.region_codes[lower(var.location)]
  instance_code       = format("%02d", var.instance)
  environment_token   = replace(var.environment_name, "-", "")
  resource_group_name = "rg-${var.workload_name}-${var.environment_name}-${local.region_code}-${local.instance_code}"
  storage_account_name = substr(
    "st${var.workload_name}${local.environment_token}${local.region_code}${local.instance_code}${var.uniqueness_code}",
    0,
    24
  )
  container_name        = "tfstate"
  private_endpoint_name = "pep-${var.workload_name}-${var.environment_name}-${local.region_code}-${local.instance_code}-blob"

  # Azure Storage rejects /31 and /32 prefixes in ipRules; individual addresses must be bare.
  storage_ip_rules = toset(flatten([
    for cidr in var.allowed_public_ipv4_cidrs :
    endswith(cidr, "/32") ? [cidrhost(cidr, 0)] :
    endswith(cidr, "/31") ? [cidrhost(cidr, 0), cidrhost(cidr, 1)] :
    [cidr]
  ]))

  state_keys = {
    bootstrap      = "${var.environment_name}/bootstrap.tfstate"
    main           = "${var.environment_name}/main.tfstate"
    capacity_probe = "${var.environment_name}/capacity-probe.tfstate"
  }

  expected_command_ids = {
    account_context      = "az_account_show"
    backend_exists       = "az_storage_account_show"
    container_exists     = "az_storage_container_show"
    dns                  = "getent_blob_endpoint"
    network              = "curl_blob_endpoint"
    authorization        = "az_storage_blob_list"
    state_key_separation = "terraform_coordinate_check"
    migration            = "terraform_state_pull"
    locking              = "terraform_lock_conflict"
  }

  managed_resource_group_id   = try(module.resource_group[0].resource_id, null)
  managed_storage_id          = try(module.storage[0].resource_id, null)
  managed_container_id        = try(module.storage[0].containers.state.id, null)
  managed_private_endpoint_id = try(module.storage[0].private_endpoints.blob.id, null)

  backend_coordinates = {
    schema_version       = "1.0"
    ownership_mode       = var.ownership_mode
    subscription_id      = var.subscription_id
    tenant_id            = var.tenant_id
    resource_group_name  = var.ownership_mode == "managed" ? local.resource_group_name : var.existing_backend.resource_group_name
    storage_account_name = var.ownership_mode == "managed" ? local.storage_account_name : var.existing_backend.storage_account_name
    container_name       = var.ownership_mode == "managed" ? local.container_name : var.existing_backend.container_name
    network_mode         = var.network_mode
    state_keys           = local.state_keys
    resource_ids = {
      resource_group  = var.ownership_mode == "managed" ? local.managed_resource_group_id : var.existing_backend.resource_group_id
      storage_account = var.ownership_mode == "managed" ? local.managed_storage_id : var.existing_backend.storage_account_id
      container       = var.ownership_mode == "managed" ? local.managed_container_id : var.existing_backend.container_id
      private_endpoint = (
        var.ownership_mode == "managed"
        ? local.managed_private_endpoint_id
        : try(var.existing_backend.private_endpoint_id, null)
      )
    }
  }

  coordinates_digest = sha256(jsonencode(local.backend_coordinates))

  existing_backend_compatible = (
    var.ownership_mode != "existing" ||
    (
      data.azurerm_storage_account.existing[0].id != "" &&
      data.azurerm_storage_container.existing[0].id != "" &&
      var.existing_backend.minimum_tls_version == "TLS1_2" &&
      var.existing_backend.https_traffic_only_enabled &&
      !var.existing_backend.shared_access_key_enabled &&
      !var.existing_backend.allow_nested_items_to_be_public &&
      var.existing_backend.infrastructure_encryption_enabled &&
      var.existing_backend.public_network_access_enabled == (var.network_mode == "restricted_public")
    )
  )

  assertion_keys_valid = (
    var.readiness_assertions != null &&
    length(setsubtract(toset(keys(try(var.readiness_assertions.checks, {}))), toset(keys(local.expected_command_ids)))) == 0 &&
    length(setsubtract(toset(keys(local.expected_command_ids)), toset(keys(try(var.readiness_assertions.checks, {}))))) == 0
  )
  assertion_commands_valid = (
    local.assertion_keys_valid &&
    alltrue([
      for key, command in local.expected_command_ids :
      try(var.readiness_assertions.checks[key].command_id, "") == command
    ])
  )
  assertion_provenance_valid = (
    local.assertion_commands_valid &&
    alltrue([
      for check in values(var.readiness_assertions.checks) :
      contains(["passed", "failed", "not_run"], check.status) &&
      (
        check.status == "not_run"
        ? check.exit_code == null && check.observed_value == ""
        : check.exit_code != null && check.observed_value != ""
      ) &&
      can(timecmp(check.observed_at, var.readiness_assertions.assessment_started_at)) &&
      can(timecmp(check.observed_at, var.readiness_assertions.assessment_completed_at)) &&
      timecmp(check.observed_at, var.readiness_assertions.assessment_started_at) >= 0 &&
      timecmp(check.observed_at, var.readiness_assertions.assessment_completed_at) <= 0
    ])
  )
  assertion_binding_valid = (
    var.readiness_assertions != null &&
    var.readiness_assertions.schema_version == "1.0" &&
    var.readiness_assertions.source_commit == var.source_commit &&
    var.readiness_assertions.coordinates_digest == local.coordinates_digest &&
    var.readiness_assertions.execution_context.network_mode == var.network_mode &&
    can(regex("^[a-f0-9]{64}$", var.readiness_assertions.execution_context.runner_context_digest)) &&
    length(var.readiness_assertions.execution_context.resolved_blob_ipv4_addresses) > 0 &&
    (
      var.network_mode == "restricted_public"
      ? try(var.readiness_assertions.execution_context.observed_public_source_ipv4, null) != null &&
      try(var.readiness_assertions.execution_context.private_network_context_digest, null) == null
      : try(var.readiness_assertions.execution_context.observed_public_source_ipv4, null) == null &&
      can(regex("^[a-f0-9]{64}$", try(var.readiness_assertions.execution_context.private_network_context_digest, "")))
    )
  )
  assertion_time_valid = (
    var.readiness_assertions != null &&
    can(timecmp(var.readiness_assertions.assessment_started_at, var.readiness_assertions.assessment_completed_at)) &&
    timecmp(var.readiness_assertions.assessment_completed_at, var.readiness_assertions.assessment_started_at) >= 0 &&
    timecmp(plantimestamp(), var.readiness_assertions.assessment_completed_at) >= 0 &&
    timecmp(plantimestamp(), timeadd(var.readiness_assertions.assessment_completed_at, "1h")) <= 0
  )

  checks = {
    for key in keys(local.expected_command_ids) :
    key => {
      status = try(var.readiness_assertions.checks[key].status, "not_run")
      detail = try(var.readiness_assertions.checks[key].detail, null)
    }
  }

  preliminary_allowed = (
    var.readiness_phase == "preliminary" &&
    alltrue([
      for key, check in local.checks :
      contains(["migration", "locking"], key)
      ? contains(["passed", "not_run"], check.status)
      : check.status == "passed"
    ])
  )
  final_allowed = (
    var.readiness_phase == "final" &&
    alltrue([for check in values(local.checks) : check.status == "passed"])
  )
  readiness_valid = (
    local.assertion_provenance_valid &&
    local.assertion_binding_valid &&
    local.assertion_time_valid &&
    (local.preliminary_allowed || local.final_allowed)
  )

  failed_check = try([
    for key in [
      "account_context",
      "backend_exists",
      "container_exists",
      "dns",
      "network",
      "authorization",
      "state_key_separation",
      "migration",
      "locking"
    ] : key if try(local.checks[key].status, "failed") == "failed"
  ][0], null)

  readiness_failure_classes = {
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

  readiness_failure_class = (
    !local.assertion_binding_valid || !local.assertion_time_valid || !local.assertion_provenance_valid ? "configuration_mismatch" :
    lookup(local.readiness_failure_classes, local.failed_check != null ? local.failed_check : "__none__", "configuration_mismatch")
  )

  lifecycle_required = contains(["migrate_local", "unlock", "destroy"], var.lifecycle_action)
  lifecycle_state_migration_valid = (
    var.lifecycle_assertions != null &&
    (
      (
        var.lifecycle_assertions.state_migration_status == "reverse_migrated" &&
        var.lifecycle_assertions.reverse_migration_verified
      ) ||
      (
        var.lifecycle_assertions.state_migration_status == "never_migrated" &&
        !var.lifecycle_assertions.reverse_migration_verified
      )
    )
  )
  lifecycle_ready = (
    local.lifecycle_required &&
    var.ownership_mode == "managed" &&
    var.lifecycle_assertions != null &&
    var.lifecycle_assertions.main_managed_resource_count == 0 &&
    var.lifecycle_assertions.probe_managed_resource_count == 0 &&
    var.lifecycle_assertions.bootstrap_state_location == "local" &&
    local.lifecycle_state_migration_valid &&
    var.lifecycle_assertions.bootstrap_state_digest != null &&
    var.lifecycle_assertions.bootstrap_state_digest == var.lifecycle_assertions.expected_state_digest &&
    trimspace(var.lifecycle_assertions.approval_reference) != ""
  )

  lifecycle_failure_class = (
    var.ownership_mode != "managed" ? "ownership_mode_forbidden" :
    var.lifecycle_assertions == null ? "configuration_mismatch" :
    var.lifecycle_assertions.main_managed_resource_count > 0 || var.lifecycle_assertions.probe_managed_resource_count > 0 ? "dependent_state_not_empty" :
    var.lifecycle_assertions.bootstrap_state_location != "local" ? "bootstrap_state_not_local" :
    !local.lifecycle_state_migration_valid ? "reverse_migration_failed" :
    var.lifecycle_assertions.bootstrap_state_digest != var.lifecycle_assertions.expected_state_digest ? "state_digest_mismatch" :
    trimspace(var.lifecycle_assertions.approval_reference) == "" ? "approval_mismatch" :
    "none"
  )
}
