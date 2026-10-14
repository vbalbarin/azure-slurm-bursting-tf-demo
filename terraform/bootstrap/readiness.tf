locals {
  backend_readiness = {
    schema_version = "1.0"
    source_commit  = var.source_commit
    assessed_at    = try(var.readiness_assertions.assessment_completed_at, "1970-01-01T00:00:00Z")
    status         = local.readiness_valid && var.readiness_phase == "final" ? "ready" : "failed"
    failure_class  = local.readiness_valid && var.readiness_phase == "final" ? "none" : local.readiness_failure_class
    identity = {
      tenant_id      = var.readiness_identity.tenant_id
      principal_id   = var.readiness_identity.principal_id
      principal_type = var.readiness_identity.principal_type
    }
    execution_context = try(var.readiness_assertions.execution_context, {
      network_mode                   = var.network_mode
      runner_context_digest          = sha256("unassessed")
      observed_public_source_ipv4    = null
      private_network_context_digest = null
      resolved_blob_ipv4_addresses   = []
      observed_at                    = "1970-01-01T00:00:00Z"
    })
    coordinates = local.backend_coordinates
    checks      = local.checks
  }
}

check "readiness_assertion_contract" {
  assert {
    condition     = var.readiness_assertions == null || (local.assertion_provenance_valid && local.assertion_binding_valid && local.assertion_time_valid)
    error_message = "Readiness assertions are stale, malformed, or do not match source, coordinates, or execution context."
  }
}
