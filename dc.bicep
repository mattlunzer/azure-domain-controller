//set region based on location of resource group
param location string = resourceGroup().location

//set vm size
param vmSize string = 'Standard_DS5_v2' //for complete list --> az vm list-sizes --location "eastus" -o table

//enable accelerated networking?
param enableAcceleratedNetworking bool = true

// disambiguate
param disambiguationPhrase string = 'ad'

//network
param nsgName string = 'nsg-${disambiguationPhrase}${uniqueString(subscription().id, resourceGroup().id)}'

//supply during deploymentcl
@secure()
param myIp string

//**inserts
@description('The DNS prefix for the public IP address used by the Load Balancer')
param dnsPrefix string

@description('The name of the administrator account of the new VM and domain')
param adminUsername string

@description('The password for the administrator account of the new VM and domain')
@secure()
param adminPassword string

@description('The location of resources, such as templates and DSC modules, that the template depends on')
param artifactsLocation string = 'https://raw.githubusercontent.com/mattlunzer/azure-domain-controller/master/'

@description('The FQDN of the Active Directory Domain to be created')
param domainName string

@description('Auto-generated token to access _artifactsLocation')
@secure()
param artifactsLocationSasToken string = ''

var storageAccountName_var = '${uniqueString(resourceGroup().id)}adsa'
var adVMName_var = 'adVM'
var adNicName_var = 'adNic'
var publicIPAddressName = 'adPublicIP'
var diskName_var = 'adOSDisk'
//**inserts

//nsg
resource nsg 'Microsoft.Network/networkSecurityGroups@2020-06-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'RDP'
        properties: {
          priority: 1000
          protocol: 'Tcp'
          access: 'Allow'
          direction: 'Inbound'
          sourceAddressPrefix: myIp
          sourcePortRange: '*'
          destinationAddressPrefix: '*'
          destinationPortRange: '3389'
        }
      }
    ]
  }
}



resource storageaccount 'Microsoft.Storage/storageAccounts@2021-02-01' = {
  name: storageAccountName_var
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_LRS'
  }
}

//public ip
resource publicIPAddress 'Microsoft.Network/publicIPAddresses@2019-11-01' = {
  name: publicIPAddressName
  location: location
    sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    dnsSettings: {
      domainNameLabel: dnsPrefix
    }
  }
  zones: [
    '1'
  ]
}

resource virtualNetwork 'Microsoft.Network/virtualNetworks@2019-11-01' existing = {
  name: 'dcVnet'
}


//nic
resource networkInterface 'Microsoft.Network/networkInterfaces@2020-11-01' = {
  name: adNicName_var
  location: location
  properties: {
    enableAcceleratedNetworking: enableAcceleratedNetworking
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: {
            id: '${virtualNetwork.id}/subnets/${'dcWorkloadSubnet'}'
          }
          publicIPAddress: {
            id: publicIPAddress.id
          }
        }
      }
    ]
  }
}

//deploy vm
resource adVMName 'Microsoft.Compute/virtualMachines@2020-12-01' = {
  name: adVMName_var
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize 
    }
    osProfile: {
      computerName: adVMName_var
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsServer'
        offer: 'WindowsServer'
        sku: '2016-Datacenter'
        version: 'latest'
      }
      osDisk: {
        name: diskName_var
        caching: 'ReadWrite'
        createOption: 'FromImage'
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: networkInterface.id
        }
      ]
    }
  }
  zones: [
    '1'
  ]
}


 resource adVMName_CreateADForest 'Microsoft.Compute/virtualMachines/extensions@2015-06-15' = {
    parent: adVMName
    name: 'CreateADForest'
    location: location
    properties: {
      publisher: 'Microsoft.Powershell'
      type: 'DSC'
      typeHandlerVersion: '2.19'
      autoUpgradeMinorVersion: true
      settings: {
        ModulesUrl: '${artifactsLocation}/DSC/CreateADPDC.zip${artifactsLocationSasToken}'
        ConfigurationFunction: 'CreateADPDC.ps1\\CreateADPDC'
        Properties: {
          DomainName: domainName
          AdminCreds: {
            UserName: adminUsername
            Password: 'PrivateSettingsRef:AdminPassword'
          }
        }
      }
      protectedSettings: {
        Items: {
          AdminPassword: adminPassword
        }
      }
    }
  }
