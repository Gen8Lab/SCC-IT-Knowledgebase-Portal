targetScope = 'resourceGroup'

param location string = resourceGroup().location

// ========================================
// APPLICATION INSIGHTS
// Used for monitoring, logging, metrics,
// availability checks and future dashboard evidence.
// ========================================
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: 'scc-kb-appinsights'
  location: location
  kind: 'web'
  properties: {
    Application_Type: 'web'
  }
}

// ========================================
// STORAGE ACCOUNT
// Used for feedback data storage and future
// portal-related cloud persistence evidence.
// ========================================
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'scckb${uniqueString(resourceGroup().id)}'
  location: location
  sku: {
    name: 'Standard_LRS'
  }
  kind: 'StorageV2'
}
// ========================================
// FEEDBACK TABLE
// Stores feedback submissions from the API.
// The table is recreated automatically when
// the infrastructure is deployed from scratch.
// ========================================
resource feedbackTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  name: '${storageAccount.name}/default/FeedbackSubmissions'
}
// ========================================
// STATIC WEB APP
// Hosts the SCC Knowledgebase frontend and
// provides the managed Azure Functions API.
// GitHub Actions deploys the application code.
// ========================================
resource staticWebApp 'Microsoft.Web/staticSites@2023-12-01' = {
  name: 'scc-kb-portal'
  location: 'westeurope'

  sku: {
    name: 'Free'
    tier: 'Free'
  }

    tags: {
    'hidden-link: /app-insights-resource-id': appInsights.id
  }

  properties: {
    repositoryUrl: 'https://github.com/Gen8Lab/SCC-IT-Knowledgebase-Portal'
    branch: 'main'
    provider: 'GitHub'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
  }
}
// ========================================
// STATIC WEB APP APPLICATION SETTINGS
// Configures the managed API with the
// storage and monitoring connections.
// Secret values are generated dynamically
// from Azure resources and are not stored
// in the source repository.
// ========================================
resource staticWebAppSettings 'Microsoft.Web/staticSites/config@2023-12-01' = {
  parent: staticWebApp
  name: 'appsettings'

  properties: {
    FEEDBACK_STORAGE_CONNECTION: 'DefaultEndpointsProtocol=https;AccountName=${storageAccount.name};AccountKey=${storageAccount.listKeys().keys[0].value};EndpointSuffix=${environment().suffixes.storage}'
    APPLICATIONINSIGHTS_CONNECTION_STRING: appInsights.properties.ConnectionString
  }
}
// ========================================
// DEPLOYMENT OUTPUTS
// Returns key resource information after an
// IaC deployment to support verification
// and repeatable rebuild procedures.
// ========================================
output staticWebAppName string = staticWebApp.name
output staticWebAppHostname string = staticWebApp.properties.defaultHostname
output storageAccountName string = storageAccount.name
output applicationInsightsName string = appInsights.name
