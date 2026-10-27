locals {
  cyclecloud_custom_role_actions = [
    "Microsoft.Authorization/*/read",
    "Microsoft.Authorization/roleAssignments/*",
    "Microsoft.Authorization/roleDefinitions/*",
    "Microsoft.Commerce/RateCard/read",
    "Microsoft.Compute/*/read",
    "Microsoft.Compute/availabilitySets/*",
    "Microsoft.Compute/disks/*",
    "Microsoft.Compute/images/read",
    "Microsoft.Compute/locations/usages/read",
    "Microsoft.Compute/register/action",
    "Microsoft.Compute/skus/read",
    "Microsoft.Compute/virtualMachines/*",
    "Microsoft.Compute/virtualMachineScaleSets/*",
    "Microsoft.Compute/virtualMachineScaleSets/virtualMachines/*",
    "Microsoft.ManagedIdentity/userAssignedIdentities/*/read",
    "Microsoft.ManagedIdentity/userAssignedIdentities/*/assign/action",
    "Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/read",
    "Microsoft.MarketplaceOrdering/offertypes/publishers/offers/plans/agreements/write",
    "Microsoft.Network/*/read",
    "Microsoft.Network/locations/*/read",
    "Microsoft.Network/networkInterfaces/read",
    "Microsoft.Network/networkInterfaces/write",
    "Microsoft.Network/networkInterfaces/delete",
    "Microsoft.Network/networkInterfaces/join/action",
    "Microsoft.Network/networkSecurityGroups/read",
    "Microsoft.Network/networkSecurityGroups/write",
    "Microsoft.Network/networkSecurityGroups/delete",
    "Microsoft.Network/networkSecurityGroups/join/action",
    "Microsoft.Network/publicIPAddresses/read",
    "Microsoft.Network/publicIPAddresses/write",
    "Microsoft.Network/publicIPAddresses/delete",
    "Microsoft.Network/publicIPAddresses/join/action",
    "Microsoft.Network/register/action",
    "Microsoft.Network/virtualNetworks/read",
    "Microsoft.Network/virtualNetworks/subnets/read",
    "Microsoft.Network/virtualNetworks/subnets/join/action",
    "Microsoft.Resources/deployments/read",
    "Microsoft.Resources/subscriptions/resourceGroups/read",
    "Microsoft.Resources/subscriptions/resourceGroups/write",
    "Microsoft.Resources/subscriptions/resourceGroups/delete",
    "Microsoft.Resources/subscriptions/resourceGroups/resources/read",
    "Microsoft.Resources/subscriptions/operationresults/read",
    "Microsoft.Storage/*/read",
    "Microsoft.Storage/checknameavailability/read",
    "Microsoft.Storage/register/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/delete",
    "Microsoft.Storage/storageAccounts/blobServices/containers/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/write",
    "Microsoft.Storage/storageAccounts/blobServices/generateUserDelegationKey/action",
    "Microsoft.Storage/storageAccounts/read",
    "Microsoft.Storage/storageAccounts/listKeys/action",
    "Microsoft.Storage/storageAccounts/write",
  ]
  cyclecloud_custom_role_data_actions = [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/delete",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/write",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/move/action",
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/add/action",
  ]
  cyclecloud_custom_role_definition_digest = sha256(jsonencode({
    actions          = local.cyclecloud_custom_role_actions
    data_actions     = local.cyclecloud_custom_role_data_actions
    not_actions      = []
    not_data_actions = []
  }))
  cyclecloud_subscription_scope = "/subscriptions/${var.subscription_id}"
  cyclecloud_vm_resource_id     = "${module.resource_group.resource_id}/providers/Microsoft.Compute/virtualMachines/${local.names.cyclecloud}"
  cyclecloud_post_create_rbac   = var.cyclecloud_identity_phase == "post-create-rbac"
  cyclecloud_system_principal_id = local.cyclecloud_post_create_rbac ? (
    data.azapi_resource.cyclecloud_vm[0].output.identity.principalId
  ) : null
}

resource "azurerm_role_definition" "cyclecloud_orchestrator" {
  #checkov:skip=CKV_AZURE_39:The reviewed Microsoft CycleCloud role requires role assignment and definition operations to attach the independent locker UAMI.
  name        = "CycleCloud ${var.subscription_id}"
  scope       = local.cyclecloud_subscription_scope
  description = "CycleCloud Orchestrator Role"

  permissions {
    actions          = local.cyclecloud_custom_role_actions
    data_actions     = local.cyclecloud_custom_role_data_actions
    not_actions      = []
    not_data_actions = []
  }

  assignable_scopes = [local.cyclecloud_subscription_scope]
}

data "azapi_resource" "cyclecloud_vm" {
  count = local.cyclecloud_post_create_rbac ? 1 : 0

  type                   = "Microsoft.Compute/virtualMachines@2024-11-01"
  resource_id            = local.cyclecloud_vm_resource_id
  response_export_values = ["identity"]
}

check "cyclecloud_system_identity_shape" {
  assert {
    condition = !local.cyclecloud_post_create_rbac || (
      data.azapi_resource.cyclecloud_vm[0].output.identity.type == "SystemAssigned" &&
      length(try(data.azapi_resource.cyclecloud_vm[0].output.identity.userAssignedIdentities, {})) == 0 &&
      local.cyclecloud_system_principal_id != null
    )
    error_message = "Post-create CycleCloud RBAC requires the exact Bicep-owned VM with only a system-assigned identity."
  }
}

module "cyclecloud_post_create_role_assignments" {
  source  = "Azure/avm-res-authorization-roleassignment/azurerm"
  version = "0.3.1"

  role_assignments_azure_resource_manager = local.cyclecloud_post_create_rbac ? {
    cyclecloud_orchestrator = {
      principal_id                     = local.cyclecloud_system_principal_id
      principal_type                   = "ServicePrincipal"
      role_definition_id               = azurerm_role_definition.cyclecloud_orchestrator.role_definition_resource_id
      scope                            = local.cyclecloud_subscription_scope
      description                      = "CycleCloud system identity orchestration permissions"
      skip_service_principal_aad_check = true
    }
    cyclecloud_key_vault_secrets_user = {
      principal_id                     = local.cyclecloud_system_principal_id
      principal_type                   = "ServicePrincipal"
      role_definition_name             = "Key Vault Secrets User"
      scope                            = module.key_vault.resource_id
      description                      = "CycleCloud bootstrap secret read"
      skip_service_principal_aad_check = true
    }
  } : {}
}
