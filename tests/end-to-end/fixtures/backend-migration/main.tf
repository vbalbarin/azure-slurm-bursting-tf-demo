terraform {
  required_version = ">= 1.10, < 2.0"
}

resource "terraform_data" "migration_marker" {
  input = "backend-migration-fixture"
}

output "migration_marker" {
  value = terraform_data.migration_marker.output
}
