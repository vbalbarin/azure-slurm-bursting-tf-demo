variable "subscription_id" {
  description = "Authorized Azure subscription ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
  }

}

variable "backend_readiness_file" {
  description = "Path to current secret-free backend readiness evidence."
  type        = string
  default     = null
  nullable    = true
}

variable "backend_readiness_json" {
  description = "Protected backend readiness JSON; intended for native tests or protected variable files when no path is available."
  type        = string
  default     = null
  nullable    = true

  validation {
    condition     = var.backend_readiness_json == null || var.backend_readiness_file == null
    error_message = "Set only one of backend_readiness_json or backend_readiness_file."
  }
}

variable "current_execution_context_digest" {
  description = "SHA-256 of the current non-secret runner/network execution context."
  type        = string
  default     = null
  nullable    = true
}

variable "deployment_source_commit" {
  description = "Exact source commit authorized for this plan."
  type        = string
  default     = null
  nullable    = true
}

variable "deployment_principal_id" {
  description = "Object ID of the active User or ServicePrincipal authorized by readiness evidence."
  type        = string
  default     = null
  nullable    = true
}

variable "backend_storage_account_name" {
  description = "Approved storage account name used by the initialized backend."
  type        = string
  default     = null
  nullable    = true
}

variable "backend_container_name" {
  description = "Approved storage container name used by the initialized backend."
  type        = string
  default     = "tfstate"
}

variable "backend_environment_name" {
  description = "Environment prefix used by the governed backend state keys."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.backend_environment_name))
    error_message = "backend_environment_name must be 3-20 lowercase alphanumeric or hyphen characters and start with a letter."
  }
}

variable "tenant_id" {
  description = "Authorized Microsoft Entra tenant ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.tenant_id))
    error_message = "tenant_id must be a UUID."
  }
}

variable "environment_name" {
  description = "Azure-safe lowercase naming prefix."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.environment_name))
    error_message = "environment_name must be 3-20 lowercase alphanumeric or hyphen characters and start with a letter."
  }
}

variable "source_region" {
  description = "Azure region for persistent management and scheduler resources."
  type        = string
}

variable "burst_region" {
  description = "Distinct Azure region for transient compute."
  type        = string

  validation {
    condition     = lower(var.burst_region) != lower(var.source_region)
    error_message = "source_region and burst_region must be different."
  }
}

variable "burst_zone" {
  description = "Operator-approved availability zone for transient burst compute."
  type        = string

  validation {
    condition     = contains(["1", "2", "3"], var.burst_zone)
    error_message = "burst_zone must be 1, 2, or 3."
  }
}

variable "alternate_burst_placements" {
  description = "Ordered operator-approved alternate burst region and availability-zone candidates."
  type = list(object({
    region = string
    zone   = string
  }))
  default = []

  validation {
    condition = alltrue([
      for placement in var.alternate_burst_placements :
      placement.region != "" &&
      contains(["1", "2", "3"], placement.zone) &&
      !(lower(placement.region) == lower(var.burst_region) && placement.zone == var.burst_zone)
    ])
    error_message = "Alternate placements require a region and zone 1-3 and must differ from the selected burst placement."
  }
}

variable "source_vnet_cidr" {
  description = "Private /16 CIDR for vnet-source."
  type        = string

  validation {
    condition     = can(cidrhost(var.source_vnet_cidr, 0)) && endswith(var.source_vnet_cidr, "/16")
    error_message = "source_vnet_cidr must be a valid /16 CIDR."
  }
}

variable "burst_vnet_cidr" {
  description = "Private, non-overlapping /16 CIDR for vnet-burst."
  type        = string

  validation {
    condition     = can(cidrhost(var.burst_vnet_cidr, 0)) && endswith(var.burst_vnet_cidr, "/16") && cidrhost(var.burst_vnet_cidr, 0) != cidrhost(var.source_vnet_cidr, 0)
    error_message = "burst_vnet_cidr must be a valid /16 CIDR and must not overlap source_vnet_cidr."
  }
}

variable "operator_group_object_ids" {
  description = "Existing Entra group object IDs authorized to administer the demo."
  type        = set(string)

  validation {
    condition     = length(var.operator_group_object_ids) > 0 && alltrue([for id in var.operator_group_object_ids : can(regex("^[0-9a-fA-F-]{36}$", id))])
    error_message = "At least one valid Entra group object ID is required."
  }
}

variable "key_vault_provisioning_access_enabled" {
  description = "Temporarily enable the Key Vault public endpoint for initial secret creation from one approved runner /32. Must be false for acceptance."
  type        = bool
  default     = false
}

variable "key_vault_provisioning_ipv4_cidrs" {
  description = "Exact approved runner IPv4 /32 used only while key_vault_provisioning_access_enabled is true."
  type        = list(string)
  default     = []

  validation {
    condition = (
      var.key_vault_provisioning_access_enabled
      ? length(var.key_vault_provisioning_ipv4_cidrs) == 1 &&
      can(cidrhost(var.key_vault_provisioning_ipv4_cidrs[0], 0)) &&
      endswith(var.key_vault_provisioning_ipv4_cidrs[0], "/32") &&
      var.key_vault_provisioning_ipv4_cidrs[0] != "0.0.0.0/32"
      : length(var.key_vault_provisioning_ipv4_cidrs) == 0
    )
    error_message = "Provisioning access requires exactly one nonzero IPv4 /32; accepted private-only mode requires no public CIDRs."
  }
}

variable "scheduler_admin_ssh_public_key" {
  description = "Scheduler administrator SSH public key generated in protected state."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^ssh-(rsa|ed25519) [A-Za-z0-9+/=]+(?: .*)?$", trimspace(var.scheduler_admin_ssh_public_key)))
    error_message = "scheduler_admin_ssh_public_key must be a valid RSA or Ed25519 OpenSSH public key."
  }
}

variable "windows_admin_password" {
  description = "Windows administrator password generated in protected state."
  type        = string
  sensitive   = true

  validation {
    condition = (
      length(var.windows_admin_password) >= 14 &&
      can(regex("[A-Z]", var.windows_admin_password)) &&
      can(regex("[a-z]", var.windows_admin_password)) &&
      can(regex("[0-9]", var.windows_admin_password)) &&
      can(regex("[^A-Za-z0-9]", var.windows_admin_password))
    )
    error_message = "windows_admin_password must be at least 14 characters and contain uppercase, lowercase, numeric, and special characters."
  }
}

variable "cyclecloud_image" {
  description = "Pinned CycleCloud Marketplace image metadata."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
    plan_name = string
    product   = string
  })

  validation {
    condition = (
      var.cyclecloud_image.publisher == "azurecyclecloud" &&
      var.cyclecloud_image.offer == "azure-cyclecloud" &&
      var.cyclecloud_image.sku == "cyclecloud8-gen2" &&
      var.cyclecloud_image.version == "8.9.320260827" &&
      var.cyclecloud_image.plan_name == "cyclecloud8-gen2" &&
      var.cyclecloud_image.product == "azure-cyclecloud"
    )
    error_message = "CycleCloud must use the pinned 8.9.3 Gen2 Marketplace image and matching plan."
  }
}

variable "scheduler_image" {
  description = "Exact-version AlmaLinux image for the persistent source-region scheduler."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })

  validation {
    condition = (
      lower(var.scheduler_image.publisher) == "almalinux" &&
      lower(var.scheduler_image.offer) == "almalinux-x86_64" &&
      can(regex("^9-gen[12]$", lower(var.scheduler_image.sku))) &&
      can(regex("^9\\.[0-9]+\\.[0-9]+$", var.scheduler_image.version))
    )
    error_message = "scheduler_image must be an exact-version AlmaLinux 9 standard x86_64 image."
  }
}

variable "burst_compute_image" {
  description = "Exact-version AlmaLinux HPC image for transient burst compute."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })

  validation {
    condition = (
      lower(var.burst_compute_image.publisher) == "almalinux" &&
      lower(var.burst_compute_image.offer) == "almalinux-hpc" &&
      can(regex("^9-hpc-gen[12]$", lower(var.burst_compute_image.sku))) &&
      can(regex("^9\\.[0-9]+\\.[0-9]+$", var.burst_compute_image.version))
    )
    error_message = "burst_compute_image must be an exact-version AlmaLinux 9 HPC image."
  }
}

variable "windows_image" {
  description = "Pinned supported Windows Server image metadata."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })

  validation {
    condition = (
      lower(var.windows_image.publisher) == "microsoftwindowsserver" &&
      lower(var.windows_image.offer) == "windowsserver" &&
      lower(var.windows_image.sku) == "2025-datacenter-azure-edition" &&
      can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.windows_image.version))
    )
    error_message = "windows_image must be an exact-version Windows Server 2025 Datacenter Azure Edition image."
  }
}

variable "cyclecloud_vm_size" {
  type        = string
  description = "Regionally available CycleCloud VM size."
}

variable "scheduler_vm_size" {
  type        = string
  description = "Regionally available scheduler VM size."
}

variable "windows_vm_size" {
  type        = string
  description = "Regionally available Windows administration VM size."
}

# tflint-ignore: terraform_unused_declarations
variable "burst_vm_size" {
  type        = string
  description = "Regionally available burst compute VM size."
}

variable "cyclecloud_vm_count" {
  description = "Planned CycleCloud VM count used for quota validation."
  type        = number
  default     = 1

  validation {
    condition     = var.cyclecloud_vm_count == 1
    error_message = "The bounded demonstration requires exactly one CycleCloud VM."
  }
}

variable "scheduler_vm_count" {
  description = "Planned scheduler VM count used for quota validation."
  type        = number
  default     = 1

  validation {
    condition     = var.scheduler_vm_count == 1
    error_message = "The bounded demonstration requires exactly one scheduler VM."
  }
}

variable "windows_vm_count" {
  description = "Planned Windows administration VM count used for quota validation."
  type        = number
  default     = 1

  validation {
    condition     = var.windows_vm_count == 1
    error_message = "The bounded demonstration requires exactly one Windows administration VM."
  }
}

variable "burst_node_count" {
  description = "Maximum simultaneously allocated burst nodes used for quota validation."
  type        = number
  default     = 1

  validation {
    condition     = var.burst_node_count == 1
    error_message = "The bounded acceptance demonstration requires exactly one burst node."
  }
}

variable "cluster_name" {
  description = "Stable cluster name used by every integration point."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{2,31}$", var.cluster_name))
    error_message = "cluster_name must be 3-32 alphanumeric or hyphen characters and start with a letter."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "idle_timeout_minutes" {
  description = "Positive idle duration before removing burst compute."
  type        = number
  default     = 10

  validation {
    condition     = var.idle_timeout_minutes > 0
    error_message = "idle_timeout_minutes must be positive."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "demo_username" {
  description = "Stable nonprivileged demonstration account name."
  type        = string
  default     = "slurmdemo"

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{2,30}$", var.demo_username))
    error_message = "demo_username must be a valid nonprivileged Linux account name."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "demo_user_uid_gid" {
  description = "Unused numeric UID and GID shared by scheduler and compute."
  type        = number
  default     = 11200

  validation {
    condition     = var.demo_user_uid_gid >= 10000 && !contains([11100, 11101], var.demo_user_uid_gid)
    error_message = "demo_user_uid_gid must be at least 10000 and differ from Slurm and Munge IDs."
  }
}

# tflint-ignore: terraform_unused_declarations
variable "cyclecloud_certificate_secret_id" {
  description = "Versioned Key Vault secret ID for the CycleCloud private TLS certificate."
  type        = string
  sensitive   = true
}

# tflint-ignore: terraform_unused_declarations
variable "chef_policy_archive_uri" {
  description = "Protected URI used by minimal bootstrap to retrieve pinned Chef policy archives."
  type        = string
  sensitive   = true
}
