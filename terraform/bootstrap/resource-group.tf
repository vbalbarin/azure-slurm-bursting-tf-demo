module "resource_group" {
  count = var.ownership_mode == "managed" ? 1 : 0

  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location = var.location
  name     = local.resource_group_name
  tags     = var.tags
}
