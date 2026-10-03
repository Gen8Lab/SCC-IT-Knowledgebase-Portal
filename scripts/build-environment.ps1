param(
    [string]$SubscriptionId = "6e870d05-9e9e-4dd2-aa09-bc11b1e433cb",
    [string]$ResourceGroupName = "rg-scc-kb-dev",
    [string]$Location = "uksouth",
    [string]$StaticWebAppName = "scc-kb-portal",
    [string]$GitHubRepo = "Gen8Lab/SCC-IT-Knowledgebase-Portal",
    [string]$GitHubSecretName = "AZURE_STATIC_WEB_APPS_API_TOKEN_GREEN_RIVER_0E5469A03",
    [string]$WorkflowName = "Azure Static Web Apps CI/CD"
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$BicepFile = Join-Path $RepoRoot "infra\main.bicep"
$VerifyScript = Join-Path $PSScriptRoot "verify-deployment.ps1"

function Write-Step {
    param([string]$Message)
    Write-Host ""
    Write-Host $Message -ForegroundColor White
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Message)
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Assert-Command {
    param([string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found."
    }
}

function Assert-LastExitCode {
    param(
        [string]$Action,
        [int]$Expected = 0
    )

    if ($LASTEXITCODE -ne $Expected) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

Write-Host ""
Write-Host "SCC IT Knowledgebase Portal - Build Environment" -ForegroundColor White
Write-Host "================================================" -ForegroundColor White

try {
    Write-Step "1. Running pre-flight checks..."

    Assert-Command "az"
    Assert-Command "gh"
    Assert-Command "git"

    if (-not (Test-Path $BicepFile)) {
        throw "Bicep file not found: $BicepFile"
    }

    if (-not (Test-Path $VerifyScript)) {
        throw "Verification script not found: $VerifyScript"
    }

    az account show --output none
    Assert-LastExitCode "Azure CLI authentication check"

    az account set --subscription $SubscriptionId
    Assert-LastExitCode "Azure subscription selection"

    gh auth status --hostname github.com 2>$null | Out-Null
    Assert-LastExitCode "GitHub CLI authentication check"

    Write-Pass "Azure and GitHub CLI pre-flight checks passed."

    Write-Step "2. Validating Bicep locally..."

    $tempBicepOutput = Join-Path $env:TEMP "scc-kb-build-validation.json"

    try {
        az bicep build --file $BicepFile --outfile $tempBicepOutput | Out-Null
        Assert-LastExitCode "Bicep build"
        Write-Pass "Bicep template builds successfully."
    }
    finally {
        if (Test-Path $tempBicepOutput) {
            Remove-Item $tempBicepOutput -Force -ErrorAction SilentlyContinue
        }
    }

    Write-Step "3. Ensuring the Azure resource group exists..."

    az group create `
        --name $ResourceGroupName `
        --location $Location `
        --output none

    Assert-LastExitCode "Resource group create/update"
    Write-Pass "Resource group is available."

    Write-Step "4. Validating the deployment with Azure..."

    az deployment group validate `
        --resource-group $ResourceGroupName `
        --template-file $BicepFile `
        --output none

    Assert-LastExitCode "Azure deployment validation"
    Write-Pass "Azure accepted the Bicep deployment definition."

    Write-Step "5. Deploying the Azure environment from Bicep..."

    $deploymentName = "scc-kb-build-{0}" -f (Get-Date -Format "yyyyMMdd-HHmmss")

    az deployment group create `
        --resource-group $ResourceGroupName `
        --template-file $BicepFile `
        --name $deploymentName `
        --output none

    Assert-LastExitCode "Bicep deployment"
    Write-Pass "Azure infrastructure deployment completed successfully."
    Write-Info "Deployment name: $deploymentName"

    Write-Step "6. Reading the rebuilt Static Web App hostname..."

    $hostname = (
        az staticwebapp show `
            --name $StaticWebAppName `
            --resource-group $ResourceGroupName `
            --query "defaultHostname" `
            --output tsv
    ).Trim()

    Assert-LastExitCode "Static Web App hostname lookup"

    if ([string]::IsNullOrWhiteSpace($hostname)) {
        throw "Azure did not return a Static Web App hostname."
    }

    $portalUrl = "https://$hostname"
    Write-Pass "Static Web App hostname resolved."
    Write-Info "Portal: $portalUrl"

    Write-Step "7. Refreshing the GitHub deployment secret..."

    $apiKey = (
        az staticwebapp secrets list `
            --name $StaticWebAppName `
            --resource-group $ResourceGroupName `
            --query "properties.apiKey" `
            --output tsv
    ).Trim()

    Assert-LastExitCode "Static Web App deployment token lookup"

    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Azure did not return a Static Web App deployment token."
    }

    try {
        $apiKey | gh secret set $GitHubSecretName --repo $GitHubRepo
        Assert-LastExitCode "GitHub secret update"
    }
    finally {
        $apiKey = $null
    }

    Write-Pass "GitHub deployment secret refreshed without displaying the token."

    Write-Step "8. Triggering the normal GitHub Actions deployment..."

    $triggerTime = [DateTime]::UtcNow.AddSeconds(-5)

    gh workflow run $WorkflowName `
        --repo $GitHubRepo `
        --ref main

    Assert-LastExitCode "GitHub workflow trigger"

    Write-Info "Waiting for the new workflow run to appear..."

    $runId = $null

    for ($attempt = 1; $attempt -le 12 -and -not $runId; $attempt++) {
        Start-Sleep -Seconds 5

        $runsJson = gh run list `
            --repo $GitHubRepo `
            --workflow $WorkflowName `
            --event workflow_dispatch `
            --branch main `
            --limit 5 `
            --json databaseId,createdAt,status,conclusion

        Assert-LastExitCode "GitHub workflow run lookup"

        $runs = $runsJson | ConvertFrom-Json

        $newRun = $runs |
            Where-Object { [DateTime]$_.createdAt -ge $triggerTime } |
            Sort-Object { [DateTime]$_.createdAt } -Descending |
            Select-Object -First 1

        if ($newRun) {
            $runId = [string]$newRun.databaseId
        }
    }

    if (-not $runId) {
        throw "The newly triggered GitHub Actions run could not be identified."
    }

    Write-Info "Workflow run ID: $runId"

    gh run watch $runId `
        --repo $GitHubRepo `
        --exit-status

    Assert-LastExitCode "GitHub Actions deployment"
    Write-Pass "GitHub Actions deployment completed successfully."

    Write-Step "9. Running automated post-deployment verification..."

    & $VerifyScript -PortalUrl $portalUrl

    if ($LASTEXITCODE -ne 0) {
        throw "Post-deployment verification failed with exit code $LASTEXITCODE."
    }

    Write-Pass "Post-deployment verification completed successfully."

    Write-Host ""
    Write-Host "================================================" -ForegroundColor White
    Write-Host "Build completed successfully" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor White
    Write-Host "Resource group : $ResourceGroupName"
    Write-Host "Portal         : $portalUrl"
    Write-Host "Workflow run   : $runId"
    Write-Host ""
    Write-Host "Infrastructure, application deployment and verification all completed." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Build stopped. Review the error above before retrying." -ForegroundColor Red
    exit 1
}
