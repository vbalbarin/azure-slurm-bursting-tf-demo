targetScope = 'resourceGroup'

@description('Azure region containing the Terraform-owned NIC.')
param location string

@description('Pinned CycleCloud virtual machine name.')
param vmName string

@description('Pinned CycleCloud virtual machine size.')
param vmSize string

@allowed([
  '1'
  '2'
  '3'
])
@description('Availability zone for the CycleCloud virtual machine.')
param zone string

@description('Resource ID of the Terraform-owned CycleCloud NIC.')
param nicResourceId string

@description('Terraform-owned control-plane user-assigned managed identity resource ID.')
param userAssignedIdentityResourceId string

@secure()
@description('Base64-encoded cloud-init payload that performs protected first-run configuration.')
param customData string

@secure()
@maxLength(80000)
@description('Base64-encoded deterministic CycleCloud Chef policy bundle.')
param chefPayloadBase64 string

@secure()
@description('Base64-encoded CycleCloud artifact manifest.')
param chefManifestBase64 string

@secure()
@description('Base64-encoded non-secret CycleCloud node specification.')
param chefNodeSpecificationBase64 string

@secure()
@description('Base64-encoded reviewed CycleCloud Policyfile lock.')
param chefPolicyLockBase64 string

@minLength(64)
@maxLength(64)
@description('SHA-256 of the decoded CycleCloud policy bundle.')
param chefPayloadSha256 string

@minLength(64)
@maxLength(64)
@description('SHA-256 of the decoded CycleCloud artifact manifest.')
param chefManifestSha256 string

@minLength(64)
@maxLength(64)
@description('SHA-256 of the decoded CycleCloud node specification.')
param chefNodeSpecificationSha256 string

@minLength(64)
@maxLength(64)
@description('SHA-256 of the decoded reviewed CycleCloud Policyfile lock.')
param chefPolicyLockSha256 string

@description('Maximum permitted decoded aggregate Chef payload size.')
@minValue(1)
@maxValue(60000)
param chefDecodedSizeBytes int

@description('Administrative Linux username.')
param adminUsername string = 'cyclecloudadmin'

@secure()
@description('Approved SSH public key whose private counterpart remains in protected state.')
param adminSshPublicKey string

@description('Pinned CycleCloud Marketplace image publisher.')
param imagePublisher string

@description('Pinned CycleCloud Marketplace image offer.')
param imageOffer string

@description('Pinned CycleCloud Marketplace image SKU.')
param imageSku string

@description('Pinned CycleCloud Marketplace image version.')
param imageVersion string

@description('Pinned CycleCloud Marketplace plan name.')
param planName string

@description('Pinned CycleCloud Marketplace plan product.')
param planProduct string

@description('Tags shared with the Terraform-owned environment.')
param tags object

resource cyclecloudVm 'Microsoft.Compute/virtualMachines@2024-11-01' = {
  name: vmName
  location: location
  zones: [
    zone
  ]
  tags: tags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${userAssignedIdentityResourceId}': {}
    }
  }
  plan: {
    name: planName
    product: planProduct
    publisher: imagePublisher
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nicResourceId
          properties: {
            primary: true
          }
        }
      ]
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      customData: customData
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: adminSshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: imagePublisher
        offer: imageOffer
        sku: imageSku
        version: imageVersion
      }
      osDisk: {
        createOption: 'FromImage'
        deleteOption: 'Delete'
        caching: 'ReadWrite'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
      dataDisks: [
        {
          lun: 0
          createOption: 'FromImage'
          deleteOption: 'Delete'
          caching: 'ReadOnly'
          managedDisk: {
            storageAccountType: 'Premium_LRS'
          }
        }
      ]
    }
  }
}

output vmResourceId string = cyclecloudVm.id
output userAssignedIdentityResourceId string = userAssignedIdentityResourceId
