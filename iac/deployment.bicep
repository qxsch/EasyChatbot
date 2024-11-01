@description('Name of the web app.')
param webAppName string = toLower('chat-${uniqueString(resourceGroup().id)}') // Generate unique String for web app name

@description('The pricing tier for the hosting plan.')
@allowed([
  'F1'
  'D1'
  'B1'
  'S1'
])
param sku string = 'B1' // The SKU of App Service Plan

@description('The instance size of the hosting plan (small, medium, or large).')
@allowed([
  '0'
  '1'
  '2'
])
param workerSize string = '0' // The instance size of the hosting plan (small, medium, or large).

@description('The location for all resources.')
param location string = 'northeurope' // Location for all resources

@description('The location for open ai and azure search resources.')
param aiLocation string = 'swedencentral' // Location for ai resources

@description('Name of the azure search.')
param azureSearchName string = toLower('search-${uniqueString(resourceGroup().id)}') // The name of the Azure Search service

@description('Name of the azure openai.')
param azureOpenAiName string = toLower('openai${uniqueString(resourceGroup().id)}') // The name of the Azure OpenAI service

@description('Name of the azure openai gpt-4o deployment.')
param gpt4oDeploymentName string = 'gpt-4o' // The name of the Azure OpenAI GPT-4o deployment

@description('Capacity of the azure openai gpt-4o deployment.')
param gpt4oDeploymentCapacity int = 450 // The capacity of the Azure OpenAI GPT-4o deployment

@description('Name of the azure openai ada text embedding deployment.')
param adaDeploymentName string = 'text-embedding-ada-002' // The name of the Azure OpenAI Ada deployment

@description('Capacity of the azure openai ada deployment.')
param adaDeploymentCapacity int = 350 // The capacity of the Azure OpenAI ada deployment

// variables
var linuxFxVersion = 'PYTHON|3.12' // The runtime stack of web app
var appServicePlanName = toLower('plan-${webAppName}')
var storageAccountName = toLower('storage${uniqueString(resourceGroup().id)}')



resource storageAccount 'Microsoft.Storage/storageAccounts@2021-04-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
  properties: {
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      virtualNetworkRules: [
      ]
    }
  }
}

resource tableService 'Microsoft.Storage/storageAccounts/tableServices@2021-04-01' = {
  name: 'default'
  parent: storageAccount
  properties: {}
}

resource historyTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2021-04-01' = {
  parent: tableService
  name: 'history'
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2021-04-01' = {
  name: 'default'
  parent: storageAccount
  properties: {}
}

resource blobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2021-04-01' = {
  parent: blobService
  name: 'documents'
}

resource appServicePlan 'Microsoft.Web/serverfarms@2022-09-01' = {
  name: appServicePlanName
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: sku
    capacity: int(workerSize)
  }
  kind: 'linux'
}

resource webApp 'Microsoft.Web/sites@2022-09-01' = {
  name: webAppName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    enabled: true
    serverFarmId: appServicePlan.id
    httpsOnly: true
    siteConfig: {
      publicNetworkAccess: 'Enabled'
      ipSecurityRestrictionsDefaultAction: 'Allow'
      scmIpSecurityRestrictionsDefaultAction: 'Allow'
      linuxFxVersion: linuxFxVersion
      alwaysOn: true
      appCommandLine: 'gunicorn --bind=0.0.0.0 --workers=4 startup:app'
      appSettings: [
        {
          name: 'STORAGE_CONNECTION_STRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=core.windows.net'
        }
        {
          name:'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value:'true'
        }
      ]
    }
  }
}


resource azureSearch 'Microsoft.Search/searchServices@2024-03-01-preview' = {
  name: azureSearchName
  location: location
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    semanticSearch: 'standard'
    disableLocalAuth: false
    authOptions: {
        aadOrApiKey: {
            aadAuthFailureMode: 'http401WithBearerChallenge'
        }
    }
  }
}





resource azureOpenAi 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: azureOpenAiName
  location: aiLocation
  sku: {
    name: 'S0'
  }
  kind: 'OpenAI'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
    publicNetworkAccess: 'Enabled'
    customSubDomainName: toLower(azureOpenAiName)
  }
}

resource azureOpenAiAdaDeplyoment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: azureOpenAi
  name: adaDeploymentName
  sku: {
    name: 'Standard'
    capacity: adaDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'text-embedding-ada-002'
      version: '2'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource azureOpenAiGpt4oDeplyoment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  parent: azureOpenAi
  name: gpt4oDeploymentName
  sku: {
    name: 'GlobalStandard'
    capacity: gpt4oDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-05-13'
    }
    versionUpgradeOption: 'OnceNewDefaultVersionAvailable'
    raiPolicyName: 'Microsoft.DefaultV2'
  }
  dependsOn: [
    azureOpenAiAdaDeplyoment
  ]
}

// give azure search access to storage account (Storage Blob Data Contributor)
resource azureSearchToStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, azureSearch.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: azureSearch.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') 
  }
  dependsOn: [
    blobService
    tableService
    historyTable
    blobContainer
  ]
}

// give open ai access to storage account (Storage Blob Data Contributor)
resource openAiToStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, azureOpenAi.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: azureOpenAi.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') 
  }
  dependsOn: [
    blobService
    tableService
    historyTable
    blobContainer
    azureOpenAiAdaDeplyoment
    azureOpenAiGpt4oDeplyoment
    azureSearchToStorage
  ]
}

// give web app access to storage account (Storage Blob Data Contributor)
resource webAppToStorage 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, 'ba92f5b4-2d11-453d-a403-e96b0029c9fe')
  scope: storageAccount
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') 
  }
  dependsOn: [
    blobService
    tableService
    historyTable
    blobContainer
    azureSearchToStorage
    openAiToStorage
  ]
}

// give web app access to storage account (Storage Table Data Contributor)
resource webAppToStorage2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, webApp.id, '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3')
  scope: storageAccount
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '0a9a7e1f-b9d0-4cc4-a60d-0319b160aaa3') 
  }
  dependsOn: [
    blobService
    tableService
    historyTable
    blobContainer
    azureSearchToStorage
    openAiToStorage
    webAppToStorage
  ]
}

// give open ai access to azure search  (Search Index Data Contributor)
resource openAiToAzureSearch1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureSearch.id, azureOpenAi.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: azureSearch
  properties: {
    principalId: azureOpenAi.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7') 
  }
  dependsOn: [
    azureOpenAiAdaDeplyoment
    azureOpenAiGpt4oDeplyoment
  ]
}
// give open ai access to azure search  (Search Index Data Reader)
resource openAiToAzureSearch2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureSearch.id, azureOpenAi.id, '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  scope: azureSearch
  properties: {
    principalId: azureOpenAi.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f') 
  }
  dependsOn: [
    azureOpenAiAdaDeplyoment
    azureOpenAiGpt4oDeplyoment
    openAiToAzureSearch1
  ]
}
// give open ai access to azure search  (Search Service Contributor)
resource openAiToAzureSearch3 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureSearch.id, azureOpenAi.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  scope: azureSearch
  properties: {
    principalId: azureOpenAi.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0') 
  }
  dependsOn: [
    azureOpenAiAdaDeplyoment
    azureOpenAiGpt4oDeplyoment
    openAiToAzureSearch1
    openAiToAzureSearch2
  ]
}

// give web app access to azure search  (Search Index Data Contributor)
resource webAppToAzureSearch1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureSearch.id, webApp.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  scope: azureSearch
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7') 
  }
  dependsOn: [
    openAiToAzureSearch1
    openAiToAzureSearch2
    openAiToAzureSearch3
  ]
}

// give web app access to azure search  (Search Index Data Reader)
resource webAppToAzureSearch2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureSearch.id, webApp.id, '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  scope: azureSearch
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f') 
  }
  dependsOn: [
    openAiToAzureSearch1
    openAiToAzureSearch2
    openAiToAzureSearch3
    webAppToAzureSearch1
  ]
}

// give azure search access to  open ai  (Cognitive Services OpenAI Contributor)
resource azureSearchToOpenAi 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureOpenAi.id, azureSearch.id, 'a001fd3d-188f-4b5d-821b-7da978bf7442')
  scope: azureOpenAi
  properties: {
    principalId: azureSearch.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', 'a001fd3d-188f-4b5d-821b-7da978bf7442') 
  }
  dependsOn: [
    azureOpenAiAdaDeplyoment
    azureOpenAiGpt4oDeplyoment
  ]
}

// give web app access to  open ai  (Cognitive Services OpenAI User)
resource webAppToOpenAi 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(azureOpenAi.id, webApp.id, '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd')
  scope: azureOpenAi
  properties: {
    principalId: webApp.identity.principalId
    roleDefinitionId: resourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') 
  }
  dependsOn: [
    azureSearchToOpenAi
  ]
}



// output the name of the web app
output webAppName string = webAppName
// output the url of the web app
output webAppUrl string = webApp.properties.defaultHostName
// output the name of the azure search
output azureSearchName string = azureSearch.name
// output the storage account name
output storageAccountName string = storageAccount.name
