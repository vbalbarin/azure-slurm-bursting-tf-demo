output "backend_coordinates" {
  description = "Non-secret backend coordinates for bootstrap, main, and capacity-probe roots."
  value       = local.backend_coordinates

  precondition {
    condition     = local.existing_backend_compatible
    error_message = "Existing backend resources do not match approved coordinates or baseline TLS/HTTPS controls."
  }
}

output "backend_readiness" {
  description = "Secret-free backend readiness evidence."
  value       = local.backend_readiness
}

output "backend_lifecycle" {
  description = "Secret-free managed backend lifecycle evidence."
  value       = local.backend_lifecycle
}
