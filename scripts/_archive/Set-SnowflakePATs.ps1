#requires -version 5.1
<#
.SYNOPSIS
    Generates Snowflake PATs for each learner and stores them in Azure Key Vault.

.DESCRIPTION
    This script replaces the manual PAT generation step.
    It is required because Snowflake provider v2.14.0 has no
    snowflake_user_programmatic_access_token resource (added in v2.17.0+).

    For each learner (APP01-APP12):
    1. Generates a PAT via Snowflake SQL (ALTER USER ... ADD PROGRAMMATIC_ACCESS_TOKEN)
    2. Stores the PAT in Azure Key Vault as SnowflakePAT-APP01, etc.

    Prerequisites:
    - Snowflake CLI (snow) configured with ACCOUNTADMIN connection
    - Azure CLI (az) logged in with access to Key Vault
    - 01-snowflake-learners Terraform module applied (users must exist)

.PARAMETER LearnerCount
    Number of learners. Default: 12.

.PARAMETER KeyVaultName
    Name of the Azure Key Vault. Default: from config/shared.env or KEY_VAULT_NAME env var.

.PARAMETER DryRun
    Show what would be done without making changes.

.EXAMPLE
    .\scripts\Set-SnowflakePATs.ps1
    .\scripts\Set-SnowflakePATs.ps1 -LearnerCount 12
    .\scripts\Set-SnowflakePATs.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [int]$LearnerCount = 12,
    [string]$KeyVaultName,
    [string]$ConnectionName = 'enterprise-pat',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# ------------------------------------------------------------------
# Resolve Key Vault name
# ------------------------------------------------------------------

if (-not $KeyVaultName) {
    $KeyVaultName = [Environment]::GetEnvironmentVariable('KEY_VAULT_NAME')
}

if (-not $KeyVaultName) {
    $sharedEnv = Join-Path $projectRoot 'config\shared.env'
    if (Test-Path $sharedEnv) {
        Get-Content $sharedEnv | ForEach-Object {
            $line = $_.Trim()
            if ($line -and $line -notmatch '^#' -and $line -match '^KEY_VAULT_NAME=') {
                $KeyVaultName = ($line -split '=', 2)[1].Trim()
            }
        }
    }
}

if (-not $KeyVaultName) {
    Write-Host '[FAIL] KEY_VAULT_NAME not set. Pass -KeyVaultName or set in config/shared.env.' -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Key Vault: $KeyVaultName" -ForegroundColor DarkGray
Write-Host "[INFO] Snowflake connection: $ConnectionName" -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Verify Snowflake CLI connection
# ------------------------------------------------------------------

Write-Host '[INFO] Testing Snowflake connection (ACCOUNTADMIN)...' -ForegroundColor DarkGray

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$testResult = & snow sql -c $ConnectionName -q "SELECT CURRENT_USER(), CURRENT_ROLE()" 2>&1
$ErrorActionPreference = $prevEAP

if ($LASTEXITCODE -ne 0) {
    Write-Host '[FAIL] Snowflake CLI connection failed' -ForegroundColor Red
    Write-Host '       Run New-SnowflakeConnection.ps1 first (with ACCOUNTADMIN PAT)' -ForegroundColor DarkGray
    exit 1
}

Write-Host '[PASS] Snowflake connection OK' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------------
# Verify Azure CLI and Key Vault access
# ------------------------------------------------------------------

if (-not $DryRun) {
    Write-Host '[INFO] Verifying Key Vault access...' -ForegroundColor DarkGray
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $kvCheck = & az keyvault show --name $KeyVaultName --query 'name' -o tsv 2>&1
    $ErrorActionPreference = $prevEAP

    if ($LASTEXITCODE -ne 0 -or -not $kvCheck) {
        Write-Host "[FAIL] Cannot access Key Vault '$KeyVaultName'" -ForegroundColor Red
        Write-Host '       Run az login first, or check RBAC assignment' -ForegroundColor DarkGray
        exit 1
    }
    Write-Host '[PASS] Key Vault accessible' -ForegroundColor Green
    Write-Host ''
}

# ------------------------------------------------------------------
# Generate PATs
# ------------------------------------------------------------------

$mode = if ($DryRun) { 'DRY RUN (no changes)' } else { 'PROVISION' }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Snowflake PAT Generation - $mode" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Learners    : $LearnerCount"
Write-Host " Key Vault   : $KeyVaultName"
Write-Host " Secret pattern: SnowflakePAT-APP01 .. SnowflakePAT-APP$($LearnerCount.ToString('D2'))"
Write-Host ''

$created = 0
$failed = 0

for ($i = 1; $i -le $LearnerCount; $i++) {
    $padded = '{0:D2}' -f $i
    $prefix = "APP$padded"
    $username = "apprenant$padded"
    $secretName = "SnowflakePAT-$prefix"

    Write-Host "-- $prefix ($username)" -ForegroundColor Cyan

    if ($DryRun) {
        Write-Host "   [DRY] Would generate PAT and store as $secretName in Key Vault" -ForegroundColor DarkGray
        $created++
        continue
    }

    # Generate PAT via Snowflake SQL
    # Syntax: ALTER USER <username> ADD PROGRAMMATIC ACCESS TOKEN <token_name>
    # The token_secret column in the output contains the PAT value.
    $tokenName = "training_pat"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $patResult = & snow sql -c $ConnectionName -q "ALTER USER IF EXISTS $username ADD PROGRAMMATIC ACCESS TOKEN $tokenName DAYS_TO_EXPIRY = 30" --format json 2>&1
    $patExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($patExit -ne 0) {
        Write-Host "   [FAIL] PAT generation failed for $username" -ForegroundColor Red
        Write-Host "         $patResult" -ForegroundColor DarkGray
        $failed++
        continue
    }

    # Parse the PAT from the JSON output
    $patValue = $null
    try {
        $jsonObj = $patResult | ConvertFrom-Json
        # The token is in the first row, first column (or in a specific field)
        if ($jsonObj[0].row[0]) {
            $patValue = $jsonObj[0].row[0]
        } elseif ($jsonObj[0].'Row 1'[0]) {
            $patValue = $jsonObj[0].'Row 1'[0]
        } elseif ($jsonObj.row) {
            $patValue = $jsonObj.row[0]
        }
    } catch {
        # Fallback: try to extract from raw text
        $text = $patResult | Out-String
        if ($text -match '"([A-Za-z0-9_\-=]{40,})"') {
            $patValue = $matches[1]
        }
    }

    if (-not $patValue) {
        Write-Host "   [FAIL] Could not parse PAT from Snowflake output" -ForegroundColor Red
        Write-Host "         Raw output: $patResult" -ForegroundColor DarkGray
        $failed++
        continue
    }

    Write-Host "   [PASS] PAT generated" -ForegroundColor Green

    # Store PAT in Key Vault
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $kvResult = & az keyvault secret set --vault-name $KeyVaultName --name $secretName --value $patValue 2>&1
    $kvExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($kvExit -eq 0) {
        Write-Host "   [PASS] Stored in Key Vault as $secretName" -ForegroundColor Green
        $created++
    } else {
        Write-Host "   [FAIL] Key Vault storage failed" -ForegroundColor Red
        Write-Host "         $kvResult" -ForegroundColor DarkGray
        $failed++
    }

    # Clear the PAT from memory
    $patValue = $null
    Write-Host ''
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Created: $created"
Write-Host "  Failed : $failed"
Write-Host ''

if ($failed -gt 0) {
    Write-Host 'Status: PARTIAL' -ForegroundColor Yellow
    exit 1
} else {
    Write-Host 'Status: DONE' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Learners can now retrieve their PAT via Learner-Login.ps1:' -ForegroundColor DarkGray
    Write-Host '  .\scripts\Learner-Login.ps1 -LearnerPrefix APP01' -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Verify PATs in Key Vault:' -ForegroundColor DarkGray
    Write-Host "  az keyvault secret list --vault-name $KeyVaultName --query `"[?starts_with(name,'SnowflakePAT')].name`" -o tsv" -ForegroundColor DarkGray
    exit 0
}
