param(
    [string]$ResourceGroupName = "rg-scc-kb-dev",
    [switch]$Force,
    [switch]$Preview
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$DestroyScript = Join-Path $PSScriptRoot "destroy-environment.ps1"
$BuildScript = Join-Path $PSScriptRoot "build-environment.ps1"

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
Write-Host "SCC IT Knowledgebase Portal - Full Environment Refresh" -ForegroundColor White
Write-Host "=======================================================" -ForegroundColor White
Write-Host ""
Write-Host "Sequence: Destroy -> Build from Bicep -> Deploy through CI/CD -> Verify" -ForegroundColor Cyan

try {
    Assert-Command "git"

    if (-not (Test-Path $DestroyScript)) {
        throw "Destroy script not found: $DestroyScript"
    }

    if (-not (Test-Path $BuildScript)) {
        throw "Build script not found: $BuildScript"
    }

    Write-Host ""
    Write-Host "1. Checking the local Git repository..."

    Push-Location $RepoRoot
    try {
        $branch = (git rev-parse --abbrev-ref HEAD).Trim()
        Assert-LastExitCode "Git branch check"

        if ($branch -ne "main") {
            throw "Refresh must be run from branch 'main'. Current branch: '$branch'."
        }

        $workingTree = git status --porcelain
        Assert-LastExitCode "Git working tree check"

        if (-not [string]::IsNullOrWhiteSpace(($workingTree -join "`n"))) {
            throw "The Git working tree is not clean. Commit or discard local changes before a destructive refresh."
        }

        git fetch origin main | Out-Null
        Assert-LastExitCode "Git fetch"

        $ahead = [int](git rev-list --count origin/main..HEAD)
        Assert-LastExitCode "Git ahead check"

        $behind = [int](git rev-list --count HEAD..origin/main)
        Assert-LastExitCode "Git behind check"

        if ($ahead -ne 0 -or $behind -ne 0) {
            throw "Local main is not fully synchronised with origin/main. Ahead: $ahead, Behind: $behind."
        }
    }
    finally {
        Pop-Location
    }

    Write-Pass "Git main is clean and synchronised with origin/main."

    Write-Host ""
    Write-Host "2. Confirming refresh scope..." -ForegroundColor White
    Write-Host ""
    Write-Host "WARNING" -ForegroundColor Red
    Write-Host "This is a destructive refresh." -ForegroundColor Yellow
    Write-Host "The current Azure resource group and its data will be deleted before being rebuilt." -ForegroundColor Yellow
    Write-Host ""

    if ($Preview) {
        Write-Info "Preview mode selected."
        Write-Info "The refresh would run the following sequence:"
        Write-Host "  1. Delete $ResourceGroupName"
        Write-Host "  2. Recreate the resource group"
        Write-Host "  3. Deploy infra/main.bicep"
        Write-Host "  4. Refresh the Static Web Apps GitHub secret"
        Write-Host "  5. Trigger the normal GitHub Actions workflow"
        Write-Host "  6. Wait for CI/CD to complete"
        Write-Host "  7. Run verify-deployment.ps1 against the rebuilt hostname"
        Write-Host ""
        Write-Info "No Azure resources were changed."
        exit 0
    }

    if (-not $Force) {
        $requiredText = "REFRESH $ResourceGroupName"
        $confirmation = Read-Host "Type '$requiredText' to continue"

        if ($confirmation -cne $requiredText) {
            Write-Info "Confirmation did not match. Refresh cancelled."
            exit 0
        }
    }
    else {
        Write-Info "Force mode enabled. Interactive refresh confirmation skipped."
    }

    Write-Host ""
    Write-Host "3. Destroying the existing environment..." -ForegroundColor White

    & $DestroyScript -ResourceGroupName $ResourceGroupName -Force

    if ($LASTEXITCODE -ne 0) {
        throw "Destroy stage failed with exit code $LASTEXITCODE."
    }

    Write-Pass "Destroy stage completed."

    Write-Host ""
    Write-Host "4. Rebuilding, deploying and verifying the environment..." -ForegroundColor White

    & $BuildScript -ResourceGroupName $ResourceGroupName

    if ($LASTEXITCODE -ne 0) {
        throw "Build stage failed with exit code $LASTEXITCODE."
    }

    Write-Pass "Build and verification stages completed."

    Write-Host ""
    Write-Host "=======================================================" -ForegroundColor White
    Write-Host "Full environment refresh completed successfully" -ForegroundColor Green
    Write-Host "=======================================================" -ForegroundColor White
    Write-Host ""
    Write-Host "The environment was destroyed, rebuilt from source-controlled Bicep," -ForegroundColor Green
    Write-Host "deployed through the normal CI/CD pipeline and verified automatically." -ForegroundColor Green
    exit 0
}
catch {
    Write-Host ""
    Write-Host "[FAIL] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Refresh stopped. Review the failed stage before retrying." -ForegroundColor Red
    exit 1
}
