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
// Provides persistence evidence for AM1.
// ========================================
resource feedbackTable 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-01-01' = {
  name: '${storageAccount.name}/default/FeedbackSubmissions'
}
