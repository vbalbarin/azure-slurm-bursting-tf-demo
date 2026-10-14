data "azurerm_storage_account" "existing" {
  count = var.ownership_mode == "existing" ? 1 : 0

  name                = var.existing_backend.storage_account_name
  resource_group_name = var.existing_backend.resource_group_name
}

data "azurerm_storage_container" "existing" {
  count = var.ownership_mode == "existing" ? 1 : 0

  name               = var.existing_backend.container_name
  storage_account_id = var.existing_backend.storage_account_id
}
