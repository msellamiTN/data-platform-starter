#requires -version 5.1
<#
.SYNOPSIS
    Learner login script - Key Vault-first authentication with local fallback.

.DESCRIPTION
    Dual-mode authentication for learners:

    Mode 1 — KV-first (preferred, no manual secret distribution):
      1. Login to Azure with the learner's AAD account (interactive browser)
      2. Fetch SP credentials (ArmClientId, ArmClientSecret, ArmTenantId,
         ArmSubscriptionId) from Key Vault
      3. Login with the SP (for Terraform provider authentication)
      4. Fetch SnowflakePAT from Key Vault
      5. Set all ARM_* and TF_VAR_snowflake_token environment variables

    Mode 2 — Local fallback (recovery, requires secrets/ files):
      1. Read SP credentials from secrets/shared-sp.txt
      2. Login with the SP
      3. Read PAT from secrets/snowflake_pat.txt
      4. Set all environment variables

    The script tries Mode 1 first. If Key Vault is inaccessible or the
    learner's AAD account can't authenticate, it falls back to Mode 2.

.PARAMETER LearnerPrefix
    Learner prefix for resource isolation (APP01, APP02, ... APP12).

.PARAMETER SecretsFile
    Path to the shared SP file. Default: secrets/shared-sp.txt
    Used only in fallback mode.

.PARAMETER ForceFallback
    Skip KV-first mode and use local secrets/ files directly.

.EXAMPLE
    .\scripts\Learner-Login.ps1 -LearnerPrefix APP01
    .\scripts\Learner-Login.ps1 -LearnerPrefix APP03 -ForceFallback
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^APP\d{2}$')]
    [string]$LearnerPrefix,
    [string]$SecretsFile,
    [switch]$ForceFallback
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$envValues = @{}

# ------------------------------------------------------------------
# Ensure local toolchain (Terraform, Snow CLI, dbt, tflint) wins over
# any system-wide installation in the current session.
# ------------------------------------------------------------------
$localBin = Join-Path $HOME '.data2ai\bin'
$localVenv = Join-Path $HOME '.data2ai\venv\Scripts'
foreach ($dir in @($localBin, $localVenv)) {
    if (Test-Path $dir) {
        $escaped = [Regex]::Escape($dir)
        if ($env:PATH -notmatch "(^|;)$escaped(;|$)") {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

if (-not $SecretsFile) {
    $SecretsFile = Join-Path $projectRoot 'secrets\shared-sp.txt'
}

# ------------------------------------------------------------------
# Load config/shared.env first (committed, shared config — no secrets)
# Then load .env (gitignored, per-learner personal values — overrides shared)
# ------------------------------------------------------------------

function Load-EnvFile {
    param([string]$Path, [hashtable]$EnvValues, [string]$Label)

    if (-not (Test-Path $Path)) { return }

    Write-Host "[INFO] Loading $Label from $Path" -ForegroundColor DarkGray

    # Detect BOM to avoid garbled content if saved as UTF-16 or with BOM.
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = 'UTF8'
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $encoding = 'Unicode'
    } elseif ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $encoding = 'UTF8'
    }

    Get-Content $Path -Encoding $encoding | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^#') {
            $sep = $line.IndexOf('=')
            if ($sep -gt 0) {
                $key = $line.Substring(0, $sep).Trim()
                $value = $line.Substring($sep + 1).Trim().Trim('"').Trim("'")
                if ($key -and $value -and -not $EnvValues.ContainsKey($key)) {
                    $EnvValues[$key] = $value
                    Set-Item -Path "env:$key" -Value $value
                }
            }
        }
    }
}

# Load shared config first (lower priority)
$sharedEnvPath = Join-Path $projectRoot 'config\shared.env'
Load-EnvFile -Path $sharedEnvPath -EnvValues $envValues -Label "shared config"

# Load .env second (higher priority — overrides shared values)
$envFile = Join-Path $projectRoot '.env'
if (Test-Path $envFile) {
    Load-EnvFile -Path $envFile -EnvValues $envValues -Label ".env"

    # Warn if important Azure variables are still empty.
    $azureVars = @('ARM_RESOURCE_GROUP', 'ARM_STORAGE_ACCOUNT', 'ARM_CONTAINER', 'ARM_LOCATION')
    foreach ($var in $azureVars) {
        if (-not [Environment]::GetEnvironmentVariable($var) -and -not $envValues[$var]) {
            Write-Host "[WARN] $var is empty or not set. Add it to .env if needed for Azure labs." -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "[WARN] No .env file found at $envFile" -ForegroundColor Yellow
    Write-Host "       Copy .env.example to .env and fill in learner-specific values." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------
# Resolve Key Vault name
# ------------------------------------------------------------------
$kvName = [Environment]::GetEnvironmentVariable('KEY_VAULT_NAME')
if (-not $kvName -and $envValues.ContainsKey('KEY_VAULT_NAME')) {
    $kvName = $envValues['KEY_VAULT_NAME']
}

# ------------------------------------------------------------------
# Helper: fetch a secret from Key Vault
# ------------------------------------------------------------------
function Get-KvSecret {
    param([string]$VaultName, [string]$SecretName)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'SilentlyContinue'
    $value = & az keyvault secret show --vault-name $VaultName --name $SecretName --query value -o tsv 2>$null
    $exit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    if ($exit -eq 0 -and $value) { return $value } else { return $null }
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Learner Login: $LearnerPrefix" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

# ------------------------------------------------------------------
# Mode 1 — KV-first (preferred)
# Learner logs in with their AAD account, fetches all secrets from KV,
# then re-logins with the SP for Terraform provider auth.
# ------------------------------------------------------------------
$kvFirstSuccess = $false
$spCreds = @{}
$patValue = $null

if (-not $ForceFallback -and $kvName) {
    Write-Host '[INFO] KV-first mode: authenticating with your AAD account...' -ForegroundColor DarkGray
    Write-Host '       A browser window will open. Login with your work/school account.' -ForegroundColor DarkGray
    Write-Host ''

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    # Try interactive login (browser). Use --allow-no-subscriptions in case
    # the learner's AAD account doesn't have a subscription directly.
    $tenantId = $envValues['ARM_TENANT_ID']
    if (-not $tenantId) { $tenantId = [Environment]::GetEnvironmentVariable('ARM_TENANT_ID') }

    $loginArgs = @('login', '--output', 'none')
    if ($tenantId) { $loginArgs += @('--tenant', $tenantId) }

    $aadLoginResult = & az @loginArgs 2>&1
    $aadLoginExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($aadLoginExit -eq 0) {
        Write-Host '[PASS] AAD login successful' -ForegroundColor Green

        # Set subscription if we know it
        $subId = $envValues['ARM_SUBSCRIPTION_ID']
        if (-not $subId) { $subId = [Environment]::GetEnvironmentVariable('ARM_SUBSCRIPTION_ID') }
        if ($subId) {
            & az account set --subscription $subId 2>&1 | Out-Null
        }

        # Fetch SP credentials from Key Vault
        Write-Host '[INFO] Fetching SP credentials from Key Vault...' -ForegroundColor DarkGray
        $spCreds['ARM_CLIENT_ID'] = Get-KvSecret -VaultName $kvName -SecretName 'ArmClientId'
        $spCreds['ARM_CLIENT_SECRET'] = Get-KvSecret -VaultName $kvName -SecretName 'ArmClientSecret'
        $spCreds['ARM_TENANT_ID'] = Get-KvSecret -VaultName $kvName -SecretName 'ArmTenantId'
        $spCreds['ARM_SUBSCRIPTION_ID'] = Get-KvSecret -VaultName $kvName -SecretName 'ArmSubscriptionId'

        $missing = @()
        foreach ($k in @('ARM_CLIENT_ID','ARM_CLIENT_SECRET','ARM_TENANT_ID','ARM_SUBSCRIPTION_ID')) {
            if (-not $spCreds[$k]) { $missing += $k }
        }

        if ($missing.Count -eq 0) {
            Write-Host '[PASS] SP credentials retrieved from Key Vault' -ForegroundColor Green

            # Persist SP credentials to secrets/shared-sp.txt for session persistence
            $secretsDir = Join-Path $projectRoot 'secrets'
            if (-not (Test-Path $secretsDir)) {
                New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
            }
            $sharedSpFile = Join-Path $secretsDir 'shared-sp.txt'
            $spContent = @(
                "# Auto-generated by Learner-Login.ps1 (KV-first mode)"
                "# DO NOT COMMIT - this file is gitignored."
                "ARM_CLIENT_ID=$($spCreds['ARM_CLIENT_ID'])"
                "ARM_CLIENT_SECRET=$($spCreds['ARM_CLIENT_SECRET'])"
                "ARM_TENANT_ID=$($spCreds['ARM_TENANT_ID'])"
                "ARM_SUBSCRIPTION_ID=$($spCreds['ARM_SUBSCRIPTION_ID'])"
            ) -join "`r`n"
            [System.IO.File]::WriteAllText($sharedSpFile, $spContent, [System.Text.UTF8Encoding]::new($false))
            Write-Host '[PASS] SP credentials persisted to secrets/shared-sp.txt' -ForegroundColor Green

            # Fetch Snowflake PAT from Key Vault
            $patValue = Get-KvSecret -VaultName $kvName -SecretName 'SnowflakePAT'
            if ($patValue) {
                Write-Host '[PASS] Snowflake PAT retrieved from Key Vault' -ForegroundColor Green

                # Persist PAT to secrets/snowflake_pat.txt for session persistence
                $patFile = Join-Path $secretsDir 'snowflake_pat.txt'
                [System.IO.File]::WriteAllText($patFile, $patValue, [System.Text.UTF8Encoding]::new($false))
                Write-Host '[PASS] Snowflake PAT persisted to secrets/snowflake_pat.txt' -ForegroundColor Green

                $kvFirstSuccess = $true
            } else {
                Write-Host '[WARN] SnowflakePAT not found in Key Vault' -ForegroundColor Yellow
                # Still proceed — PAT can come from fallback
            }
        } else {
            Write-Host "[WARN] Missing SP secrets in Key Vault: $($missing -join ', ')" -ForegroundColor Yellow
            Write-Host '       Falling back to local secrets file.' -ForegroundColor DarkGray
        }
    } else {
        Write-Host '[WARN] AAD login failed or cancelled.' -ForegroundColor Yellow
        Write-Host '       Falling back to local secrets file.' -ForegroundColor DarkGray
    }
    Write-Host ''
}

# ------------------------------------------------------------------
# Mode 2 — Local fallback (recovery)
# Read SP credentials from secrets/shared-sp.txt and PAT from
# secrets/snowflake_pat.txt.
# ------------------------------------------------------------------
if (-not $kvFirstSuccess) {
    Write-Host '[INFO] Fallback mode: using local secrets files...' -ForegroundColor DarkGray

    if (-not (Test-Path $SecretsFile)) {
        Write-Host "[FAIL] Shared SP file not found: $SecretsFile" -ForegroundColor Red
        Write-Host "       KV-first mode also failed." -ForegroundColor DarkGray
        Write-Host "       Ask your instructor for:" -ForegroundColor DarkGray
        Write-Host "         - Key Vault access (Data2AI-Learners group RBAC)" -ForegroundColor DarkGray
        Write-Host "         - Or: secrets/shared-sp.txt + secrets/snowflake_pat.txt" -ForegroundColor DarkGray
        exit 1
    }

    # Parse shared SP file
    $spCreds = @{}
    Get-Content $SecretsFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^#') {
            $idx = $line.IndexOf('=')
            if ($idx -gt 0) {
                $key = $line.Substring(0, $idx).Trim()
                $val = $line.Substring($idx + 1).Trim()
                $spCreds[$key] = $val
            }
        }
    }

    $required = @('ARM_CLIENT_ID','ARM_CLIENT_SECRET','ARM_TENANT_ID','ARM_SUBSCRIPTION_ID')
    foreach ($k in $required) {
        if (-not $spCreds.ContainsKey($k)) {
            Write-Host "[FAIL] Missing $k in $SecretsFile" -ForegroundColor Red
            exit 1
        }
    }

    # Try to fetch PAT from Key Vault (using SP login) or local file
    if (-not $patValue -and $kvName) {
        # Login with SP first, then try KV
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $spLoginResult = & az login --service-principal `
            -u $spCreds['ARM_CLIENT_ID'] `
            -p $spCreds['ARM_CLIENT_SECRET'] `
            --tenant $spCreds['ARM_TENANT_ID'] 2>&1
        $spLoginExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($spLoginExit -eq 0) {
            $patValue = Get-KvSecret -VaultName $kvName -SecretName 'SnowflakePAT'
            if ($patValue) {
                Write-Host '[PASS] Snowflake PAT retrieved from Key Vault (via SP)' -ForegroundColor Green
            }
        } else {
            Write-Host '[WARN] SP login for KV fetch failed - will retry below.' -ForegroundColor Yellow
            Write-Host "       $spLoginResult" -ForegroundColor DarkGray
        }
    }

    # Fallback: local PAT file
    if (-not $patValue) {
        $patFile = Join-Path $projectRoot 'secrets\snowflake_pat.txt'
        if (Test-Path $patFile) {
            $patValue = (Get-Content $patFile -Encoding UTF8 -Raw).Trim()
            if ($patValue) {
                Write-Host '[PASS] Snowflake PAT loaded from local file' -ForegroundColor Green
            }
        }
    }
}

# ------------------------------------------------------------------
# Login with SP — the lab session must end as the service principal.
# Runs whenever the earlier SP-then-KV attempt did NOT succeed
# ($spLoginExit -ne 0 or never attempted, e.g. after KV-first where
# the session is still the AAD user). The AAD user lacks data-plane
# roles (blob write fails); the SP has Storage Blob Data Contributor.
# ------------------------------------------------------------------
if ($spLoginExit -ne 0) {
    Write-Host '[INFO] Logging in with shared service principal...' -ForegroundColor DarkGray

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $loginResult = & az login --service-principal `
        -u $spCreds['ARM_CLIENT_ID'] `
        -p $spCreds['ARM_CLIENT_SECRET'] `
        --tenant $spCreds['ARM_TENANT_ID'] 2>&1
    $loginExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($loginExit -ne 0) {
        Write-Host "[FAIL] SP login failed" -ForegroundColor Red
        Write-Host "       $loginResult" -ForegroundColor DarkGray
        exit 1
    }
}

# Set subscription
& az account set --subscription $spCreds['ARM_SUBSCRIPTION_ID'] 2>&1 | Out-Null

$subName = & az account show --query 'name' -o tsv 2>&1
Write-Host ''
Write-Host "[PASS] Logged in to Azure" -ForegroundColor Green
Write-Host "       Subscription: $subName ($($spCreds['ARM_SUBSCRIPTION_ID']))" -ForegroundColor DarkGray
Write-Host "       Tenant: $($spCreds['ARM_TENANT_ID'])" -ForegroundColor DarkGray
Write-Host "       Learner prefix: $LearnerPrefix" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# Set ARM environment variables for Terraform
# ------------------------------------------------------------------
$env:ARM_CLIENT_ID = $spCreds['ARM_CLIENT_ID']
$env:ARM_CLIENT_SECRET = $spCreds['ARM_CLIENT_SECRET']
$env:ARM_TENANT_ID = $spCreds['ARM_TENANT_ID']
$env:ARM_SUBSCRIPTION_ID = $spCreds['ARM_SUBSCRIPTION_ID']
$env:LEARNER_PREFIX = $LearnerPrefix

# ------------------------------------------------------------------
# Set TF_VAR_snowflake_token
# ------------------------------------------------------------------
if ($patValue) {
    $env:TF_VAR_snowflake_token = $patValue
    Write-Host '[PASS] TF_VAR_snowflake_token set' -ForegroundColor Green
} else {
    Write-Host '[WARN] PAT not found. Terraform will prompt for var.snowflake_token.' -ForegroundColor Yellow
    Write-Host '       Fix: ask instructor to set SnowflakePAT in Key Vault' -ForegroundColor DarkGray
    Write-Host '       Or:  run .\scripts\New-SnowflakeConnection.ps1 to create a local PAT file' -ForegroundColor DarkGray
}

# Clear sensitive values from memory
$patValue = $null
$spCreds['ARM_CLIENT_SECRET'] = $null

Write-Host ''
Write-Host '[PASS] Environment variables set:' -ForegroundColor Green
Write-Host '       ARM_CLIENT_ID' -ForegroundColor DarkGray
Write-Host '       ARM_CLIENT_SECRET (hidden)' -ForegroundColor DarkGray
Write-Host '       ARM_TENANT_ID' -ForegroundColor DarkGray
Write-Host '       ARM_SUBSCRIPTION_ID' -ForegroundColor DarkGray
Write-Host "       LEARNER_PREFIX = $LearnerPrefix" -ForegroundColor DarkGray
Write-Host ''

Write-Host '[INFO] PATH updated for this session. Local tools in .data2ai\bin and .data2ai\venv\Scripts take priority.' -ForegroundColor DarkGray
Write-Host ''

Write-Host 'Verify (PowerShell):' -ForegroundColor Cyan
Write-Host '  $env:ARM_SUBSCRIPTION_ID' -ForegroundColor DarkGray
Write-Host '  $env:ARM_RESOURCE_GROUP' -ForegroundColor DarkGray
Write-Host '  $env:ARM_STORAGE_ACCOUNT' -ForegroundColor DarkGray
Write-Host '  $env:ARM_CONTAINER' -ForegroundColor DarkGray
Write-Host '  $env:ARM_LOCATION' -ForegroundColor DarkGray
Write-Host '  $env:LEARNER_PREFIX' -ForegroundColor DarkGray
Write-Host ''

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Ready for labs' -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor DarkGray
Write-Host '  .\scripts\Test-LabConnectivity.ps1 -SkipDevOps' -ForegroundColor DarkGray
Write-Host ''

$localTerraform = Join-Path $HOME '.data2ai\bin\terraform.exe'
if (Test-Path $localTerraform) {
    $tfVersion = & $localTerraform version 2>&1 | Select-Object -First 1
    Write-Host "       terraform version -> $tfVersion" -ForegroundColor DarkGray
} else {
    Write-Host '[WARN] terraform.exe not found in .data2ai\bin' -ForegroundColor Yellow
    Write-Host '       Run: .\scripts\Install-Tools.ps1' -ForegroundColor Yellow
}
