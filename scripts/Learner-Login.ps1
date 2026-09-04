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
    Learner prefix for resource isolation (APP01, APP02, ... APP12).
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
$envValues = @{} 

# ------------------------------------------------------------------
# Ensure local toolchain (Terraform, Snow CLI, dbt, tflint) wins over
# any system-wide installation in the current session.
# ------------------------------------------------------------------
$localBin = Join-Path $HOME '.data2ai\bin'
$localVenv = Join-Path $HOME '.data2ai\venv\Scripts'
$localDbtVenv = Join-Path $HOME '.data2ai\venv-dbt\Scripts'
foreach ($dir in @($localBin, $localVenv, $localDbtVenv)) {
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

if (-not (Test-Path $SecretsFile)) {
    Write-Host "[FAIL] Shared SP file not found: $SecretsFile" -ForegroundColor Red
    Write-Host "       Ask your instructor for the shared-sp.txt file" -ForegroundColor DarkGray
    exit 1
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

# ------------------------------------------------------------------
# Set TF_VAR_snowflake_token so Terraform can read the PAT without
# prompting. The shared PAT is in secrets/snowflake_pat.txt (gitignored).
# All learners share the same PAT (DATA2AI user with SYSADMIN role).
# Resource isolation is via LEARNER_PREFIX in resource names + state files.
# Never display or log the token.
# ------------------------------------------------------------------

$patRetrieved = $false
$patFile = Join-Path $projectRoot 'secrets\snowflake_pat.txt'

if (Test-Path $patFile) {
    $patValue = (Get-Content $patFile -Encoding UTF8 -Raw).Trim()
    if ($patValue) {
        $env:TF_VAR_snowflake_token = $patValue
        $patRetrieved = $true
        Write-Host '       TF_VAR_snowflake_token (from shared PAT file)' -ForegroundColor DarkGray
    }
}

if (-not $patRetrieved) {
    Write-Host '[WARN] PAT not found. Terraform will prompt for var.snowflake_token.' -ForegroundColor Yellow
    Write-Host '       Fix: run .\scripts\New-SnowflakeConnection.ps1 to create the PAT file' -ForegroundColor DarkGray
    Write-Host '       Or:  ask instructor to provide secrets/snowflake_pat.txt' -ForegroundColor DarkGray
}

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
Write-Host '[INFO] PATH updated for this session. Local tools in .data2ai\bin and .data2ai\venv\Scripts take priority.' -ForegroundColor DarkGray

$localTerraform = Join-Path $HOME '.data2ai\bin\terraform.exe'
if (Test-Path $localTerraform) {
    $tfVersion = & $localTerraform version 2>&1 | Select-Object -First 1
    Write-Host "       terraform version -> $tfVersion" -ForegroundColor DarkGray
} else {
    Write-Host '[WARN] terraform.exe not found in .data2ai\bin' -ForegroundColor Yellow
    Write-Host '       Run: .\scripts\Install-Tools.ps1' -ForegroundColor Yellow
}
