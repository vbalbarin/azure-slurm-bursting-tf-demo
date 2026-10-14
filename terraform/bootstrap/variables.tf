variable "subscription_id" {
  description = "Approved Azure subscription UUID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", var.subscription_id))
    error_message = "subscription_id must be a valid UUID."
  }
}

variable "tenant_id" {
  description = "Approved Microsoft Entra tenant UUID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$", var.tenant_id))
    error_message = "tenant_id must be a valid UUID."
  }
}

variable "location" {
  description = "Approved Azure region with a defined naming code."
  type        = string

  validation {
    condition = contains([
      "centralus",
      "eastus",
      "eastus2",
      "northcentralus",
      "southcentralus",
      "westcentralus",
      "westus",
      "westus2",
      "westus3"
    ], lower(var.location))
    error_message = "location must be present in the approved region-code map."
  }
}

variable "workload_name" {
  description = "Lowercase ALZ workload token."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,7}$", var.workload_name))
    error_message = "workload_name must be 2-8 lowercase alphanumeric characters and start with a letter."
  }
}

variable "environment_name" {
  description = "Lowercase environment token and Blob key prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,7}$", var.environment_name))
    error_message = "environment_name must be 2-8 lowercase alphanumeric or hyphen characters and start with a letter."
  }
}

variable "instance" {
  description = "Backend instance number."
  type        = number

  validation {
    condition     = var.instance >= 0 && var.instance <= 99 && floor(var.instance) == var.instance
    error_message = "instance must be an integer from 0 through 99."
  }
}

variable "uniqueness_code" {
  description = "Stable operator-supplied global-name uniqueness code."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{4,6}$", var.uniqueness_code))
    error_message = "uniqueness_code must contain four to six lowercase alphanumeric characters."
  }
}

variable "ownership_mode" {
  description = "Whether this root manages or only validates the backend."
  type        = string
  default     = "managed"

  validation {
    condition     = contains(["managed", "existing"], var.ownership_mode)
    error_message = "ownership_mode must be managed or existing."
  }
}

variable "network_mode" {
  description = "Approved backend network mode."
  type        = string
  default     = "restricted_public"

  validation {
    condition     = contains(["restricted_public", "private"], var.network_mode)
    error_message = "network_mode must be restricted_public or private."
  }
}

variable "operator_group_object_id" {
  description = "Existing Entra operator security-group object ID; required in managed mode."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ownership_mode == "existing" ||
      (
        var.operator_group_object_id != null &&
        can(regex("^[0-9a-fA-F-]{36}$", var.operator_group_object_id))
      )
    )
    error_message = "managed mode requires an operator_group_object_id UUID."
  }
}

variable "workload_identity_object_id" {
  description = "Optional approved workload service-principal object ID."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.workload_identity_object_id == null || can(regex("^[0-9a-fA-F-]{36}$", var.workload_identity_object_id))
    error_message = "workload_identity_object_id must be null or a UUID."
  }
}

variable "allowed_public_ipv4_cidrs" {
  description = "Explicit approved public IPv4 CIDRs for restricted-public mode."
  type        = set(string)
  default     = []

  validation {
    condition = (
      var.network_mode != "restricted_public" ||
      (
        length(var.allowed_public_ipv4_cidrs) > 0 &&
        alltrue([
          for cidr in var.allowed_public_ipv4_cidrs :
          can(cidrhost(cidr, 0)) &&
          cidr != "0.0.0.0/0" &&
          !can(regex("^(10\\.|192\\.168\\.|172\\.(1[6-9]|2[0-9]|3[01])\\.)", cidr))
        ])
      )
    )
    error_message = "restricted_public mode requires explicit public IPv4 CIDRs and rejects RFC1918 and 0.0.0.0/0 ranges."
  }

  validation {
    condition     = var.network_mode != "private" || length(var.allowed_public_ipv4_cidrs) == 0
    error_message = "private mode rejects allowed_public_ipv4_cidrs."
  }
}

variable "private_endpoint_subnet_id" {
  description = "Existing reachable subnet resource ID for private managed mode."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ownership_mode != "managed" ||
      var.network_mode != "private" ||
      (
        var.private_endpoint_subnet_id != null &&
        can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.private_endpoint_subnet_id))
      )
    )
    error_message = "private managed mode requires a valid private_endpoint_subnet_id."
  }
}

variable "private_dns_zone_id" {
  description = "Existing privatelink.blob.core.windows.net private DNS zone ID for private managed mode."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition = (
      var.ownership_mode != "managed" ||
      var.network_mode != "private" ||
      (
        var.private_dns_zone_id != null &&
        endswith(lower(var.private_dns_zone_id), "/privatelink.blob.core.windows.net")
      )
    )
    error_message = "private managed mode requires the privatelink.blob.core.windows.net private DNS zone resource ID."
  }
}

variable "existing_backend" {
  description = "Approved organizational backend coordinates for validate-only existing mode."
  type = object({
    resource_group_name               = string
    resource_group_id                 = string
    storage_account_name              = string
    storage_account_id                = string
    container_name                    = string
    container_id                      = string
    private_endpoint_id               = optional(string)
    private_endpoint_subnet_id        = optional(string)
    private_dns_zone_id               = optional(string)
    public_network_access_enabled     = bool
    shared_access_key_enabled         = bool
    allow_nested_items_to_be_public   = bool
    infrastructure_encryption_enabled = bool
    minimum_tls_version               = string
    https_traffic_only_enabled        = bool
  })
  default  = null
  nullable = true

  validation {
    condition = (
      (var.ownership_mode == "existing" && var.existing_backend != null) ||
      (var.ownership_mode == "managed" && var.existing_backend == null)
    )
    error_message = "existing mode requires existing_backend; managed mode rejects it."
  }

  validation {
    condition = (
      var.ownership_mode != "existing" ||
      var.network_mode != "private" ||
      (
        try(var.existing_backend.private_endpoint_subnet_id, null) != null &&
        try(var.existing_backend.private_dns_zone_id, null) != null
      )
    )
    error_message = "private existing mode requires approved subnet and private DNS coordinates."
  }
}

variable "tags" {
  description = "Approved non-secret governance tags."
  type        = map(string)

  validation {
    condition = (
      length(var.tags) > 0 &&
      alltrue([
        for key, value in var.tags :
        trimspace(key) != "" &&
        trimspace(value) != "" &&
        !can(regex("(?i)(secret|password|token|credential|key)", key))
      ])
    )
    error_message = "tags must be non-empty and must not use secret-shaped keys."
  }
}

variable "source_commit" {
  description = "Exact source commit authorized by readiness evidence."
  type        = string

  validation {
    condition     = can(regex("^[a-f0-9]{40}$", var.source_commit))
    error_message = "source_commit must be a 40-character lowercase Git SHA."
  }
}

variable "readiness_identity" {
  description = "Non-secret identity context for readiness evidence."
  type = object({
    tenant_id      = string
    principal_id   = string
    principal_type = string
  })

  validation {
    condition = (
      var.readiness_identity.tenant_id == var.tenant_id &&
      contains(["User", "ServicePrincipal"], var.readiness_identity.principal_type) &&
      can(regex("^[0-9a-fA-F-]{36}$", var.readiness_identity.principal_id))
    )
    error_message = "readiness_identity must match tenant_id and identify a User or ServicePrincipal."
  }
}

variable "readiness_assertions" {
  description = "Protected provenance-bearing readiness assertions; null before assessment."
  type = object({
    schema_version          = string
    source_commit           = string
    coordinates_digest      = string
    assessment_started_at   = string
    assessment_completed_at = string
    execution_context = object({
      network_mode                   = string
      runner_context_digest          = string
      observed_public_source_ipv4    = optional(string)
      private_network_context_digest = optional(string)
      resolved_blob_ipv4_addresses   = set(string)
      observed_at                    = string
    })
    checks = map(object({
      command_id     = string
      observed_at    = string
      exit_code      = optional(number)
      status         = string
      observed_value = string
      detail         = optional(string)
    }))
  })
  default  = null
  nullable = true
}

variable "readiness_phase" {
  description = "Preliminary or final readiness classification."
  type        = string
  default     = "preliminary"

  validation {
    condition     = contains(["preliminary", "final"], var.readiness_phase)
    error_message = "readiness_phase must be preliminary or final."
  }
}

variable "lifecycle_action" {
  description = "Managed backend lifecycle action."
  type        = string
  default     = "operate"

  validation {
    condition     = contains(["operate", "migrate_local", "unlock", "destroy"], var.lifecycle_action)
    error_message = "lifecycle_action must be operate, migrate_local, unlock, or destroy."
  }

  validation {
    condition = (
      var.lifecycle_action == "operate" ||
      (
        var.ownership_mode == "managed" &&
        var.lifecycle_assertions != null &&
        try(var.lifecycle_assertions.main_managed_resource_count, -1) == 0 &&
        try(var.lifecycle_assertions.probe_managed_resource_count, -1) == 0 &&
        try(var.lifecycle_assertions.bootstrap_state_location, "") == "local" &&
        try(var.lifecycle_assertions.reverse_migration_verified, false) &&
        try(var.lifecycle_assertions.bootstrap_state_digest, null) != null &&
        try(var.lifecycle_assertions.bootstrap_state_digest, null) == try(var.lifecycle_assertions.expected_state_digest, null) &&
        trimspace(try(var.lifecycle_assertions.approval_reference, "")) != ""
      )
    )
    error_message = "Lifecycle actions require managed ownership, empty dependent states, verified local migration, matching state digests, and an approval reference."
  }
}

variable "lifecycle_assertions" {
  description = "Protected lifecycle assertions required for removal actions."
  type = object({
    assessed_at                  = string
    approval_reference           = string
    main_state_status            = string
    main_managed_resource_count  = number
    probe_state_status           = string
    probe_managed_resource_count = number
    bootstrap_state_location     = string
    bootstrap_state_digest       = optional(string)
    expected_state_digest        = optional(string)
    reverse_migration_verified   = bool
  })
  default  = null
  nullable = true
}
