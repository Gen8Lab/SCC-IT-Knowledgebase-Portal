param(
    [string]$SubscriptionId = "6e870d05-9e9e-4dd2-aa09-bc11b1e433cb",
    [string]$ResourceGroupName = "rg-scc-kb-dev",
    [switch]$Force,
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

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
    param([string]$Action)

    if ($LASTEXITCODE -ne 0) {
        throw "$Action failed with exit code $LASTEXITCODE."
    }
}

Write-Host ""
Write-Host "SCC IT Knowledgebase Portal - Destroy Environment" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor White

try {
    Assert-Command "az"

    az account show --output none
    Assert-LastExitCode "Azure CLI authentication check"

    az account set --subscription $SubscriptionId
    Assert-LastExitCode "Azure subscription selection"

    $groupExists = az group exists --name $ResourceGroupName
    Assert-LastExitCode "Resource group existence check"

    if ($groupExists.Trim().ToLower() -ne "true") {
        Write-Pass "Resource group '$ResourceGroupName' does not exist. Nothing to delete."
        exit 0
    }

    Write-Host ""
    Write-Host "Resources currently inside ${ResourceGroupName}:" -ForegroundColor Yellow

    az resource list `
        --resource-group $ResourceGroupName `
        --query "[].{Name:name,Type:type}" `
        --output table

    Assert-LastExitCode "Resource inventory"

    Write-Host ""
    Write-Host "WARNING" -ForegroundColor Red
    Write-Host "This deletes the complete resource group, including Table Storage data," -ForegroundColor Yellow
    Write-Host "Application Insights telemetry and the Static Web App." -ForegroundColor Yellow
    Write-Host ""

    if ($Preview) {
        Write-Info "Preview mode selected. No Azure resources were deleted."
        Write-Info "An actual run would delete resource group '$ResourceGroupName'."
        exit 0
    }

    if (-not $Force) {
        $requiredText = "DELETE $ResourceGroupName"
        $confirmation = Read-Host "Type '$requiredText' to continue"

        if ($confirmation -cne $requiredText) {
            Write-Info "Confirmation did not match. Destruction cancelled."
            exit 0
        }
    }
    else {
        Write-Info "Force mode supplied by an orchestration script. Interactive confirmation skipped."
    }

    Write-Host ""
    Write-Info "Deleting resource group '$ResourceGroupName'..."

    az group delete `
        --name $ResourceGroupName `
        --yes

    Assert-LastExitCode "Resource group deletion"

    $stillExists = az group exists --name $ResourceGroupName
    Assert-LastExitCode "Post-delete resource group check"

    if ($stillExists.Trim().ToLower() -ne "false") {
        throw "Azure still reports that resource group '$ResourceGroupName' exists."
    }

    Write-Pass "Resource group deletion completed and absence was independently verified."
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Destroy operation stopped." -ForegroundColor Red
    exit 1
}
