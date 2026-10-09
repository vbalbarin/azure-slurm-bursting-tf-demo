variable "subscription_id" {
  type        = string
  description = "Authorized Azure subscription ID."
}

variable "tenant_id" {
  type        = string
  description = "Authorized Microsoft Entra tenant ID."
}

variable "environment_name" {
  type        = string
  description = "Azure-safe prefix shared with the demonstration."

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,19}$", var.environment_name))
    error_message = "environment_name must be 3-20 lowercase alphanumeric or hyphen characters."
  }
}

variable "burst_region" {
  type        = string
  description = "Exact operator-selected burst region."
}

variable "burst_zone" {
  type        = string
  description = "Exact operator-selected burst availability zone."

  validation {
    condition     = contains(["1", "2", "3"], var.burst_zone)
    error_message = "burst_zone must be 1, 2, or 3."
  }
}

variable "burst_vm_size" {
  type        = string
  description = "Exact burst VM size to allocate once."
}

variable "burst_compute_image" {
  description = "Exact-version burst image."
  type = object({
    publisher = string
    offer     = string
    sku       = string
    version   = string
  })
}

variable "probe_vnet_cidr" {
  type        = string
  description = "Isolated private CIDR used only by the capacity probe."
  default     = "10.254.0.0/24"

  validation {
    condition     = can(cidrhost(var.probe_vnet_cidr, 0))
    error_message = "probe_vnet_cidr must be a valid CIDR."
  }
}

variable "expires_at" {
  type        = string
  description = "UTC expiration timestamp recorded on every temporary resource."

  validation {
    condition = (
      can(timecmp(var.expires_at, timestamp())) &&
      timecmp(var.expires_at, timestamp()) > 0 &&
      timecmp(var.expires_at, timeadd(timestamp(), "24h")) <= 0
    )
    error_message = "expires_at must be a future RFC 3339 timestamp no more than 24 hours away."
  }
}

variable "owner" {
  type        = string
  description = "Accountable operator identifier recorded as a tag; must not contain a secret."
}

variable "cost_acknowledged" {
  type        = bool
  description = "Explicit acknowledgement that the temporary allocation can incur Azure charges."

  validation {
    condition     = var.cost_acknowledged
    error_message = "cost_acknowledged must be true before a probe plan can be created."
  }
}
