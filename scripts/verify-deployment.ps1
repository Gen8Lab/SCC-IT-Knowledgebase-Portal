param(
    [string]$PortalUrl = "https://brave-sand-02fdec103.5.azurestaticapps.net"
)

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ApiPath = Join-Path $RepoRoot "api"
$BicepFile = Join-Path $RepoRoot "infra\main.bicep"
$TempBicepOutput = Join-Path $env:TEMP "scc-kb-main-validation.json"

$passed = 0
$failed = 0

function Write-Pass {
    param([string]$Message)
    $script:passed++
    Write-Host "[PASS] $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Fail {
    param([string]$Message)
    $script:failed++
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Get-HttpStatusFromException {
    param($Exception)

    if ($Exception.Response -and $Exception.Response.StatusCode) {
        return [int]$Exception.Response.StatusCode
    }

    return $null
}

Write-Host ""
Write-Host "SCC IT Knowledgebase Portal - Automated Verification" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor White
Write-Host ""
Write-Info "Repository root: $RepoRoot"
Write-Info "Portal: $PortalUrl"
Write-Host ""

# ------------------------------------------------------------
# 1. Validate the Bicep template
# ------------------------------------------------------------
Write-Host "1. Validating Bicep infrastructure..."
try {
    if (-not (Test-Path $BicepFile)) {
        throw "Bicep file not found: $BicepFile"
    }

    az bicep build --file $BicepFile --outfile $TempBicepOutput | Out-Null

    if ($LASTEXITCODE -ne 0) {
        throw "az bicep build returned exit code $LASTEXITCODE"
    }

    Write-Pass "Bicep template builds successfully."
}
catch {
    Write-Fail "Bicep validation failed: $($_.Exception.Message)"
}
finally {
    if (Test-Path $TempBicepOutput) {
        Remove-Item $TempBicepOutput -Force -ErrorAction SilentlyContinue
    }
}

Write-Host ""

# ------------------------------------------------------------
# 2. Run the API unit tests
# ------------------------------------------------------------
Write-Host "2. Running API unit tests..."
try {
    if (-not (Test-Path $ApiPath)) {
        throw "API folder not found: $ApiPath"
    }

    Push-Location $ApiPath

    if (-not (Test-Path (Join-Path $ApiPath "node_modules"))) {
        Write-Info "node_modules not found. Running npm ci first..."
        npm ci

        if ($LASTEXITCODE -ne 0) {
            throw "npm ci returned exit code $LASTEXITCODE"
        }
    }

    npm test -- --runInBand

    if ($LASTEXITCODE -ne 0) {
        throw "Unit tests returned exit code $LASTEXITCODE"
    }

    Write-Pass "All API unit tests passed."
}
catch {
    Write-Fail "API unit tests failed: $($_.Exception.Message)"
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
}

Write-Host ""

# ------------------------------------------------------------
# 3. Check production dependencies for known vulnerabilities
# ------------------------------------------------------------
Write-Host "3. Checking production dependencies..."
try {
    Push-Location $ApiPath
    npm audit --omit=dev

    if ($LASTEXITCODE -ne 0) {
        throw "npm audit --omit=dev returned exit code $LASTEXITCODE"
    }

    Write-Pass "Production dependency audit completed with no blocking vulnerabilities."
}
catch {
    Write-Fail "Production dependency audit failed: $($_.Exception.Message)"
}
finally {
    Pop-Location -ErrorAction SilentlyContinue
}

Write-Host ""

# ------------------------------------------------------------
# 4. Confirm the live portal is available over HTTPS
# ------------------------------------------------------------
Write-Host "4. Checking live portal availability..."
try {
    $portalResponse = Invoke-WebRequest -Uri $PortalUrl -Method Get -UseBasicParsing

    if ([int]$portalResponse.StatusCode -ne 200) {
        throw "Expected HTTP 200 but received $($portalResponse.StatusCode)"
    }

    Write-Pass "Live portal returned HTTP 200 over HTTPS."
}
catch {
    Write-Fail "Live portal check failed: $($_.Exception.Message)"
}

Write-Host ""

# ------------------------------------------------------------
# 5. Confirm GET is not accepted by the feedback endpoint
# ------------------------------------------------------------
Write-Host "5. Checking feedback API method restriction..."
try {
    try {
        Invoke-WebRequest -Uri "$PortalUrl/api/feedback" -Method Get -UseBasicParsing | Out-Null
        throw "GET unexpectedly succeeded."
    }
    catch {
        $status = Get-HttpStatusFromException $_.Exception

        if ($status -eq 404 -or $status -eq 405) {
            Write-Pass "Feedback API rejected GET as expected (HTTP $status)."
        }
        elseif ($_.Exception.Message -eq "GET unexpectedly succeeded.") {
            throw
        }
        else {
            throw "Expected HTTP 404/405 but received $status. $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Fail "Feedback API method check failed: $($_.Exception.Message)"
}

Write-Host ""

# ------------------------------------------------------------
# 6. Confirm invalid feedback is rejected
# ------------------------------------------------------------
Write-Host "6. Checking feedback validation..."
try {
    $invalidBody = @{ message = "   " } | ConvertTo-Json

    try {
        Invoke-WebRequest `
            -Uri "$PortalUrl/api/feedback" `
            -Method Post `
            -ContentType "application/json" `
            -Body $invalidBody `
            -UseBasicParsing | Out-Null

        throw "Whitespace-only feedback unexpectedly succeeded."
    }
    catch {
        $status = Get-HttpStatusFromException $_.Exception

        if ($status -eq 400) {
            Write-Pass "Whitespace-only feedback was rejected with HTTP 400."
        }
        elseif ($_.Exception.Message -eq "Whitespace-only feedback unexpectedly succeeded.") {
            throw
        }
        else {
            throw "Expected HTTP 400 but received $status. $($_.Exception.Message)"
        }
    }
}
catch {
    Write-Fail "Feedback validation check failed: $($_.Exception.Message)"
}

Write-Host ""

# ------------------------------------------------------------
# 7. Confirm a valid feedback submission works end to end
# ------------------------------------------------------------
Write-Host "7. Checking live feedback submission..."
try {
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $verificationMessage = "Automated deployment verification - $timestamp"
    $validBody = @{ message = $verificationMessage } | ConvertTo-Json

    $apiResponse = Invoke-RestMethod `
        -Uri "$PortalUrl/api/feedback" `
        -Method Post `
        -ContentType "application/json" `
        -Body $validBody

    if ($apiResponse.message -ne "Feedback received successfully.") {
        throw "Unexpected API response: $($apiResponse | ConvertTo-Json -Compress)"
    }

    Write-Pass "Valid feedback submission completed successfully."
    Write-Info "Test record: $verificationMessage"
}
catch {
    Write-Fail "Live feedback submission failed: $($_.Exception.Message)"
}

Write-Host ""
Write-Host "====================================================" -ForegroundColor White
Write-Host "Verification summary" -ForegroundColor White
Write-Host "====================================================" -ForegroundColor White
Write-Host "Passed: $passed" -ForegroundColor Green

if ($failed -eq 0) {
    Write-Host "Failed: 0" -ForegroundColor Green
    Write-Host ""
    Write-Host "All automated verification checks passed." -ForegroundColor Green
    exit 0
}
else {
    Write-Host "Failed: $failed" -ForegroundColor Red
    Write-Host ""
    Write-Host "One or more verification checks failed." -ForegroundColor Red
    exit 1
}
