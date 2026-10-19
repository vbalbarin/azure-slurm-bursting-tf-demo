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
    type: 'SystemAssigned'
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
output principalId string = cyclecloudVm.identity.principalId
