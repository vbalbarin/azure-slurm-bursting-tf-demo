variable "subscription_id" {
  description = "Authorized Azure subscription ID."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F-]{36}$", var.subscription_id))
    error_message = "subscription_id must be a UUID."
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
  description = "Pinned supported AlmaLinux HPC image metadata."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "windows_image" {
  description = "Pinned supported Windows Server image metadata."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
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
