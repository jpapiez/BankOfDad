// Infrastructure for running the deploy/ compose stack on one small Azure VM.
// Holds no app configuration or secrets: deploy.sh pushes those with `az vm run-command` after this deploys.
// See deploy/azure/README.md.

@description('Azure region. Defaults to the resource group\'s region.')
param location string = resourceGroup().location

@description('Prefix for resource names.')
@minLength(3)
@maxLength(20)
param namePrefix string = 'bankofdad'

@description('VM size. Standard_B2ats_v2 (x64, 2 vCPU, 1 GiB) is the cheapest that runs the stack comfortably with swap. For Arm (e.g. Standard_B2pts_v2) set osImageSku to server-arm64.')
param vmSize string = 'Standard_B2ats_v2'

@description('Ubuntu 24.04 LTS image SKU: server (x64) or server-arm64.')
@allowed([
  'server'
  'server-arm64'
])
param osImageSku string = 'server'

@description('OS disk size in GiB. Postgres data lives here.')
@minValue(30)
param osDiskSizeGB int = 30

param adminUsername string = 'azureuser'

@description('SSH public key for adminUsername. No inbound ports are open, so this is only usable from inside the VNet or over the serial console.')
param sshPublicKey string = ''

@description('True when the VM already exists. Azure can\'t change customData or SSH keys on an existing VM, so osProfile is left out on redeploys. deploy.sh sets this.')
param vmExists bool = false

@description('Days to keep nightly database backups in Blob storage.')
@minValue(1)
param backupRetentionDays int = 30

var cloudInit = loadTextContent('cloud-init.yaml')
var storageName = take('${replace(toLower(namePrefix), '-', '')}${uniqueString(resourceGroup().id)}', 24)
var backupContainerName = 'backups'
// Storage Blob Data Contributor
var blobContributorRoleId = 'ba92f5b4-2d11-453d-a403-e96b0029c9fe'

// No allow rules: the default rules deny all inbound traffic from the internet.
resource nsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: '${namePrefix}-nsg'
  location: location
  properties: {
    securityRules: []
  }
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: '${namePrefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: ['10.20.0.0/24']
    }
    subnets: [
      {
        name: 'default'
        properties: {
          addressPrefix: '10.20.0.0/26'
          networkSecurityGroup: { id: nsg.id }
          defaultOutboundAccess: false
        }
      }
    ]
  }
}

// Explicit outbound internet access (image pulls, apt, Tailscale). The NSG blocks all inbound.
resource publicIp 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: '${namePrefix}-ip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    publicIPAddressVersion: 'IPv4'
  }
}

resource nic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: '${namePrefix}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: { id: vnet.properties.subnets[0].id }
          privateIPAllocationMethod: 'Dynamic'
          publicIPAddress: {
            id: publicIp.id
            properties: { deleteOption: 'Delete' }
          }
        }
      }
    ]
  }
}

resource vm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
  name: '${namePrefix}-vm'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    securityProfile: {
      securityType: 'TrustedLaunch'
      uefiSettings: {
        secureBootEnabled: true
        vTpmEnabled: true
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: 'ubuntu-24_04-lts'
        sku: osImageSku
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        diskSizeGB: osDiskSizeGB
        deleteOption: 'Delete'
        managedDisk: {
          storageAccountType: 'StandardSSD_LRS'
        }
      }
    }
    osProfile: vmExists ? null : {
      computerName: namePrefix
      adminUsername: adminUsername
      customData: base64(cloudInit)
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: nic.id
          properties: { deleteOption: 'Delete' }
        }
      ]
    }
    // Managed boot diagnostics, which also enables the serial console.
    diagnosticsProfile: {
      bootDiagnostics: {
        enabled: true
      }
    }
  }
}

resource storage 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
  properties: {
    accessTier: 'Hot'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    minimumTlsVersion: 'TLS1_2'
    supportsHttpsTrafficOnly: true
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage
  name: 'default'
}

resource backupContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: blobService
  name: backupContainerName
  properties: {
    publicAccess: 'None'
  }
}

resource backupExpiry 'Microsoft.Storage/storageAccounts/managementPolicies@2023-05-01' = {
  parent: storage
  name: 'default'
  properties: {
    policy: {
      rules: [
        {
          name: 'expire-backups'
          enabled: true
          type: 'Lifecycle'
          definition: {
            filters: {
              blobTypes: ['blockBlob']
              prefixMatch: ['${backupContainerName}/']
            }
            actions: {
              baseBlob: {
                delete: { daysAfterCreationGreaterThan: backupRetentionDays }
              }
            }
          }
        }
      ]
    }
  }
}

// The VM uploads backups with its managed identity; no storage keys exist.
resource vmCanWriteBackups 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: backupContainer
  name: guid(backupContainer.id, vm.id, blobContributorRoleId)
  properties: {
    principalId: vm.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', blobContributorRoleId)
  }
}

output vmName string = vm.name
output backupStorageAccount string = storage.name
output backupContainer string = backupContainer.name
