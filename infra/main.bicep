targetScope = 'resourceGroup'

param location string = resourceGroup().location

// ========================================
// APPLICATION INSIGHTS
// Provides an Azure monitoring resource
// linked to the Static Web App.
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
// Provides persistent cloud storage for
// feedback submitted through the API.
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
// FUNCTION ERROR METRIC ALERT
// Monitors the managed API using the native
// Azure Static Web Apps FunctionErrors metric.
//
// The alert is evaluated every minute and
// triggers when one or more function errors
// occur during a five-minute monitoring window.
//
// No notification action is currently attached.
// The rule still provides automated detection
// and alert-state monitoring in Azure Monitor.
// ========================================
resource functionErrorAlert 'Microsoft.Insights/metricAlerts@2018-03-01' = {
  name: 'scc-kb-function-errors'
  location: 'global'

  properties: {
    description: 'Alert when the SCC Knowledgebase managed API records one or more function errors.'
    severity: 2
    enabled: true
    autoMitigate: true

    scopes: [
      staticWebApp.id
    ]

    evaluationFrequency: 'PT1M'
    windowSize: 'PT5M'

    criteria: {
      'odata.type': 'Microsoft.Azure.Monitor.SingleResourceMultipleMetricCriteria'

      allOf: [
        {
          criterionType: 'StaticThresholdCriterion'
          name: 'FunctionErrorsCondition'
          metricName: 'FunctionErrors'
          metricNamespace: 'Microsoft.Web/staticSites'
          timeAggregation: 'Total'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: []
          skipMetricValidation: false
        }
      ]
    }

    actions: []
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
output functionErrorAlertName string = functionErrorAlert.name
