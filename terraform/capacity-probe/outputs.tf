output "probe" {
  description = "Secret-free point-in-time capacity-probe result."
  value = {
    resource_group_name = module.resource_group.name
    virtual_machine_id  = module.virtual_machine.resource_id
    region              = var.burst_region
    zone                = var.burst_zone
    vm_size             = var.burst_vm_size
    image_urn = join(":", [
      var.burst_compute_image.publisher,
      var.burst_compute_image.offer,
      var.burst_compute_image.sku,
      var.burst_compute_image.version
    ])
    expires_at = var.expires_at
    guarantee  = "point_in_time_only"
  }
}
