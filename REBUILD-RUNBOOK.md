# SCC IT Knowledgebase Portal - Azure Rebuild Runbook

## Purpose

This runbook documents the controlled process used to destroy and rebuild the SCC IT Knowledgebase Portal Azure environment from Infrastructure as Code (IaC).

The rebuild demonstrates that the environment is reproducible rather than dependent on manually configured Azure resources.

The process covers:

- Azure resource destruction and recreation.
- Infrastructure deployment using Bicep.
- Azure Static Web Apps configuration.
- Secure refresh of the GitHub Actions deployment token.
- Automated unit testing through the CI/CD quality gate.
- Application deployment through GitHub Actions.
- API and persistence verification.
- Application Insights monitoring verification.

---

## Architecture Recreated

The Bicep deployment provisions and configures:

- Azure Static Web App: `scc-kb-portal`
- Azure managed Functions API
- Azure Storage Account
- Azure Table Storage table: `FeedbackSubmissions`
- Azure Application Insights: `scc-kb-appinsights`
- Static Web App application settings
- Application Insights association

Application source code is subsequently deployed from GitHub through GitHub Actions.

---

## Prerequisites

Before beginning a rebuild:

1. Open the repository in VS Code.
2. Confirm the repository is on the `main` branch.
3. Confirm the working tree is clean.
4. Confirm Azure CLI authentication.
5. Confirm GitHub CLI authentication.
6. Confirm the Bicep template builds successfully.
7. Confirm the latest source code is pushed to GitHub.
8. Back up any stateful feedback data that must be preserved.

### Pre-Rebuild Checks

```powershell
git status

az account show `
  --query "{Name:name, SubscriptionId:id, State:state}" `
  --output table

gh auth status

az bicep build --file .\infra\main.bicep
---

## Controlled Destruction and Infrastructure Reconstruction

### 1. Final Safety Check

Immediately before deleting the Azure environment:

```powershell
git status
```

Expected result:

```text
On branch main
Your branch is up to date with 'origin/main'.

nothing to commit, working tree clean
```

Confirm the local feedback backup still exists:

```powershell
Get-Item .\feedback-backup-before-rebuild.json
```

### 2. Delete the Azure Resource Group

> WARNING: This command deletes the Azure environment, including the Static Web App, Storage Account, Table Storage data and Application Insights resource.

```powershell
az group delete `
  --name rg-scc-kb-dev `
  --yes
```

Do not continue until Azure confirms that the resource group has been deleted.

Verify deletion:

```powershell
az group exists --name rg-scc-kb-dev
```

Expected result:

```text
false
```

### 3. Recreate the Resource Group

```powershell
az group create `
  --name rg-scc-kb-dev `
  --location uksouth
```

Verify that the resource group exists:

```powershell
az group exists --name rg-scc-kb-dev
```

Expected result:

```text
true
```

### 4. Validate the Bicep Template

Before deployment:

```powershell
az bicep build --file .\infra\main.bicep
```

Then perform Azure server-side validation:

```powershell
az deployment group validate `
  --resource-group rg-scc-kb-dev `
  --template-file .\infra\main.bicep
```

The validation must report:

```text
provisioningState: Succeeded
```

### 5. Rebuild the Azure Infrastructure

Deploy the environment from Bicep:

```powershell
az deployment group create `
  --resource-group rg-scc-kb-dev `
  --template-file .\infra\main.bicep `
  --name scc-kb-rebuild
```

The deployment must complete with:

```text
provisioningState: Succeeded
```

The Bicep template recreates the core Azure architecture and dynamically configures the Storage and Application Insights connection settings.

### 6. Retrieve Deployment Outputs

After the deployment succeeds:

```powershell
az deployment group show `
  --resource-group rg-scc-kb-dev `
  --name scc-kb-rebuild `
  --query properties.outputs `
  --output table
```

The deployment outputs provide the recreated:

- Static Web App name
- Static Web App hostname
- Storage Account name
- Application Insights name

The Static Web App hostname may change following a clean rebuild. Verification should therefore use the hostname returned by the new deployment rather than assuming the previous hostname remains valid.
---

## Reconnect GitHub Actions and Deploy the Application

A newly created Azure Static Web App receives a new deployment API token.

The GitHub Actions repository secret therefore needs to be refreshed after a clean rebuild. The token must not be displayed, stored in source code, or copied into documentation.

### 7. Refresh the GitHub Actions Deployment Secret

Confirm that the expected GitHub Actions secret exists:

```powershell
gh secret list `
  --repo Gen8Lab/SCC-IT-Knowledgebase-Portal
```

Expected secret name:

```text
AZURE_STATIC_WEB_APPS_API_TOKEN_GREEN_RIVER_0E5469A03
```

Retrieve the new Static Web App deployment token from Azure and pipe it directly into GitHub:

```powershell
az staticwebapp secrets list `
  --name scc-kb-portal `
  --resource-group rg-scc-kb-dev `
  --query "properties.apiKey" `
  --output tsv |
gh secret set AZURE_STATIC_WEB_APPS_API_TOKEN_GREEN_RIVER_0E5469A03 `
  --repo Gen8Lab/SCC-IT-Knowledgebase-Portal
```

This method prevents the deployment token from being printed to the terminal or stored in the repository.

Verify that GitHub recorded the secret update:

```powershell
gh secret list `
  --repo Gen8Lab/SCC-IT-Knowledgebase-Portal
```

The deployment secret should show a recent `UPDATED` timestamp.

### 8. Trigger the CI/CD Pipeline

The infrastructure deployment recreates the Azure resources, but the application source still needs to be deployed from GitHub.

Trigger the existing GitHub Actions workflow:

```powershell
gh workflow run "Azure Static Web Apps CI/CD" `
  --repo Gen8Lab/SCC-IT-Knowledgebase-Portal
```

Monitor the workflow:

```powershell
gh run watch `
  --repo Gen8Lab/SCC-IT-Knowledgebase-Portal
```

The pipeline must successfully complete:

1. Repository checkout.
2. API dependency installation.
3. Jest API unit tests.
4. Static Web App build and deployment.

The deployment must not proceed if the automated unit tests fail.

### 9. Confirm the Rebuilt Static Web App Hostname

Retrieve the hostname from Azure rather than relying on the hostname from the previous environment:

```powershell
$hostname = az staticwebapp show `
  --name scc-kb-portal `
  --resource-group rg-scc-kb-dev `
  --query "defaultHostname" `
  --output tsv

$hostname
```

This hostname is used for all post-rebuild application and API verification.
