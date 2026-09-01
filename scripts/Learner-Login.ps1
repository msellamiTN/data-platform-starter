#requires -version 5.1
<#
.SYNOPSIS
    Learner login script - authenticates to Azure using the shared service principal.

.DESCRIPTION
    Reads the shared SP credentials from secrets/shared-sp.txt and logs in.
    Sets ARM_* environment variables for Terraform.
    Sets LEARNER_PREFIX for resource isolation.

    No MFA required - service principals bypass MFA enforcement.

.PARAMETER LearnerPrefix
    Learner prefix for resource isolation (APP01, APP02, ... APP10).
    This is used in Snowflake resource names and Terraform state file paths.

.PARAMETER SecretsFile
    Path to the shared SP file. Default: secrets/shared-sp.txt

.EXAMPLE
    .\scripts\Learner-Login.ps1 -LearnerPrefix APP01
    .\scripts\Learner-Login.ps1 -LearnerPrefix APP03 -SecretsFile .\secrets\shared-sp.txt
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^APP\d{2}$')]
    [string]$LearnerPrefix,
    [string]$SecretsFile
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

if (-not $SecretsFile) {
    $SecretsFile = Join-Path $projectRoot 'secrets\shared-sp.txt'
}

if (-not (Test-Path $SecretsFile)) {
    Write-Host "[FAIL] Shared SP file not found: $SecretsFile" -ForegroundColor Red
    Write-Host "       Ask your instructor for the shared-sp.txt file" -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------
# Parse shared SP file
# ------------------------------------------------------------------

$creds = @{}
Get-Content $SecretsFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^#') {
        $idx = $line.IndexOf('=')
        if ($idx -gt 0) {
            $key = $line.Substring(0, $idx).Trim()
            $val = $line.Substring($idx + 1).Trim()
            $creds[$key] = $val
        }
    }
}

$required = @('ARM_CLIENT_ID','ARM_CLIENT_SECRET','ARM_TENANT_ID','ARM_SUBSCRIPTION_ID')
foreach ($k in $required) {
    if (-not $creds.ContainsKey($k)) {
        Write-Host "[FAIL] Missing $k in $SecretsFile" -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------------------------------
# Login
# ------------------------------------------------------------------

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Learner Login: $LearnerPrefix" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

Write-Host '[INFO] Logging in with shared service principal...' -ForegroundColor DarkGray

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$loginResult = & az login --service-principal `
    -u $creds['ARM_CLIENT_ID'] `
    -p $creds['ARM_CLIENT_SECRET'] `
    --tenant $creds['ARM_TENANT_ID'] 2>&1
$loginExit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($loginExit -ne 0) {
    Write-Host "[FAIL] Login failed" -ForegroundColor Red
    Write-Host "       $loginResult" -ForegroundColor DarkGray
    exit 1
}

# Set subscription
& az account set --subscription $creds['ARM_SUBSCRIPTION_ID'] 2>&1 | Out-Null

$subName = & az account show --query 'name' -o tsv 2>&1
Write-Host "[PASS] Logged in to Azure" -ForegroundColor Green
Write-Host "       Subscription: $subName ($($creds['ARM_SUBSCRIPTION_ID']))" -ForegroundColor DarkGray
Write-Host "       Tenant: $($creds['ARM_TENANT_ID'])" -ForegroundColor DarkGray
Write-Host "       Learner prefix: $LearnerPrefix" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# Set ARM environment variables for Terraform
# ------------------------------------------------------------------

$env:ARM_CLIENT_ID = $creds['ARM_CLIENT_ID']
$env:ARM_CLIENT_SECRET = $creds['ARM_CLIENT_SECRET']
$env:ARM_TENANT_ID = $creds['ARM_TENANT_ID']
$env:ARM_SUBSCRIPTION_ID = $creds['ARM_SUBSCRIPTION_ID']
$env:LEARNER_PREFIX = $LearnerPrefix

Write-Host '[PASS] Environment variables set:' -ForegroundColor Green
Write-Host '       ARM_CLIENT_ID' -ForegroundColor DarkGray
Write-Host '       ARM_CLIENT_SECRET (hidden)' -ForegroundColor DarkGray
Write-Host '       ARM_TENANT_ID' -ForegroundColor DarkGray
Write-Host '       ARM_SUBSCRIPTION_ID' -ForegroundColor DarkGray
Write-Host "       LEARNER_PREFIX = $LearnerPrefix" -ForegroundColor DarkGray
Write-Host ''

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Ready for labs' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor DarkGray
Write-Host '  .\scripts\Test-LabConnectivity.ps1 -SkipDevOps' -ForegroundColor DarkGray
Write-Host ''
