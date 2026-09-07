#requires -version 5.1
<#
.SYNOPSIS
    Clear all Azure connections and stale credentials from previous sessions.

.DESCRIPTION
    Removes every trace of a previous Azure login before a fresh
    Learner-Login.ps1 run:

      1. az logout            — signs out the current CLI account
      2. az account clear     — wipes ALL cached CLI accounts/subscriptions
      3. az cache purge       — clears the CLI local cache
      4. Disconnect-AzAccount — signs out the Az PowerShell module (if installed)
      5. Clear-AzContext      — removes the Az module context cache (if installed)
      6. Unsets ARM_* / TF_VAR_* / LEARNER_PREFIX / KEY_VAULT_NAME env vars
         left over from a previous service-principal session.

    Run this FIRST when you switch learner accounts or when Terraform picks
    up the wrong service principal / subscription.

.EXAMPLE
    .\scripts\Clear-AzSession.ps1
    .\scripts\Clear-AzSession.ps1 -KeepEnvVars   # only clear az sessions
#>

[CmdletBinding()]
param(
    [switch]$KeepEnvVars
)

$ErrorActionPreference = 'Continue'   # never abort on a missing tool

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Clearing previous Azure connections' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# 1-3. Azure CLI: logout + clear all cached accounts + purge cache
# ------------------------------------------------------------------
$azCmd = Get-Command az -ErrorAction SilentlyContinue
if ($azCmd) {
    Write-Host '[INFO] az logout ...' -ForegroundColor DarkGray
    & az logout 2>&1 | Out-Null

    Write-Host '[INFO] az account clear (all cached accounts) ...' -ForegroundColor DarkGray
    & az account clear 2>&1 | Out-Null

    Write-Host '[INFO] az cache purge ...' -ForegroundColor DarkGray
    & az cache purge 2>&1 | Out-Null

    Write-Host '[PASS] Azure CLI sessions cleared' -ForegroundColor Green
} else {
    Write-Host '[SKIP] az CLI not found in PATH' -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# 4-5. Az PowerShell module (if installed)
# ------------------------------------------------------------------
if (Get-Module -ListAvailable -Name Az.Accounts) {
    try {
        Import-Module Az.Accounts -ErrorAction Stop
        Disconnect-AzAccount -ErrorAction SilentlyContinue | Out-Null
        Clear-AzContext -Force -ErrorAction SilentlyContinue | Out-Null
        Write-Host '[PASS] Az PowerShell module context cleared' -ForegroundColor Green
    } catch {
        Write-Host "[WARN] Az module cleanup failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }
} else {
    Write-Host '[SKIP] Az PowerShell module not installed' -ForegroundColor DarkGray
}

# ------------------------------------------------------------------
# 6. Clear leftover environment variables (session scope)
# ------------------------------------------------------------------
if (-not $KeepEnvVars) {
    $varsToClear = @(
        'ARM_CLIENT_ID',
        'ARM_CLIENT_SECRET',
        'ARM_TENANT_ID',
        'ARM_SUBSCRIPTION_ID',
        'ARM_USE_AZUREAD',
        'ARM_USE_OIDC',
        'ARM_ACCESS_KEY',
        'TF_VAR_snowflake_token',
        'TF_VAR_rsa_public_key',
        'LEARNER_PREFIX',
        'KEY_VAULT_NAME',
        'AZURE_CONFIG_DIR'   # only if a previous session overrode it
    )
    foreach ($v in $varsToClear) {
        if (Test-Path "env:$v") {
            Remove-Item "env:$v" -ErrorAction SilentlyContinue
            Write-Host "       cleared `$env:$v" -ForegroundColor DarkGray
        }
    }
    Write-Host '[PASS] Session environment variables cleared' -ForegroundColor Green
} else {
    Write-Host '[SKIP] -KeepEnvVars specified, env vars untouched' -ForegroundColor DarkGray
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Clean slate — run Learner-Login.ps1 to authenticate' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next step:' -ForegroundColor DarkGray
Write-Host '  .\scripts\Learner-Login.ps1 -LearnerPrefix APP01' -ForegroundColor DarkGray
