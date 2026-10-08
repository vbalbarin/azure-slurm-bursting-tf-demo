module "resource_group" {
  source  = "Azure/avm-res-resources-resourcegroup/azurerm"
  version = "0.4.0"

  location         = var.source_region
  name             = local.resource_group_name
  enable_telemetry = false
  tags             = local.common_tags
}

module "log_analytics" {
  source  = "Azure/avm-res-operationalinsights-workspace/azurerm"
  version = "0.5.1"

  location                                  = var.source_region
  name                                      = local.names.log_analytics
  resource_group_name                       = module.resource_group.name
  log_analytics_workspace_retention_in_days = 90
  enable_telemetry                          = false
  tags                                      = local.common_tags
}
