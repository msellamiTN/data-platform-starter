#requires -version 5.1
<#
.SYNOPSIS
    Reset a specific lab environment — destroy Terraform resources and drop
    leftover Snowflake objects for that lab only.

.DESCRIPTION
    Run this BEFORE starting a lab to ensure a clean state, or AFTER a lab
    to clean up resources.

    Each lab uses module-specific resource names (e.g. APP01_M05_RAW_DEV)
    so Reset-Lab only drops resources belonging to the specified lab.
    Other labs' resources are untouched.

.PARAMETER LearnerPrefix
    Learner prefix (APP01, APP02, ... APP12).

.PARAMETER Lab
    Lab identifier (M01, M02, ... M14). Case-insensitive.

.PARAMETER Environment
    Environment suffix (DEV, UAT, PROD). Default: DEV

.EXAMPLE
    .\scripts\Reset-Lab.ps1 -LearnerPrefix APP01 -Lab M05
    .\scripts\Reset-Lab.ps1 -LearnerPrefix APP01 -Lab M01 -Environment UAT
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidatePattern('^APP\d{2}$')]
    [string]$LearnerPrefix,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^M\d{2}$', Options='IgnoreCase')]
    [string]$Lab,

    [string]$Environment = "DEV"
)

$ErrorActionPreference = 'Continue'

# Normalize lab ID to uppercase (M01, M05, etc.)
$Lab = $Lab.ToUpper()

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# Map lab IDs to directory names
$labDirs = @{
    "M01" = "m01-iac-workflow"
    "M02" = "m02-state-management"
    "M03" = "m03-import-brownfield"
    "M04" = "m04-variables-outputs"
    "M05" = "m05-modules"
    "M06" = "m06-dynamic-logic"
    "M07" = "m07-cicd-pipeline"
    "M08" = "m08-environments"
    "M09" = "m09-snowflake-advanced"
    "M10" = "m10-security-auth"
    "M11" = "m11-rbac"
    "M12" = "m12-capstone"
    "M13" = "m13-finops-observability"
    "M14" = "m14-data-products"
}

if (-not $labDirs.ContainsKey($Lab)) {
    Write-Host "[ERROR] Unknown lab: $Lab. Valid values: M01-M14." -ForegroundColor Red
    exit 1
}

$labDirName = $labDirs[$Lab]
$labDir = Join-Path $projectRoot "labs\$labDirName"

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Lab Reset: $Lab" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Learner prefix : $LearnerPrefix" -ForegroundColor DarkGray
Write-Host "  Lab            : $Lab ($labDirName)" -ForegroundColor DarkGray
Write-Host "  Environment    : $Environment" -ForegroundColor DarkGray
Write-Host "  Lab directory  : labs\$labDirName" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# 1. Terraform destroy (if state exists in the lab directory)
# ------------------------------------------------------------------

if (Test-Path $labDir) {
    $stateFile = Join-Path $labDir 'terraform.tfstate'
    if (Test-Path $stateFile) {
        Write-Host "[1/3] Running terraform destroy in labs\$labDirName..." -ForegroundColor Yellow

        Push-Location $labDir
        try {
            # Ensure terraform is in PATH
            $localBin = Join-Path $HOME '.data2ai\bin'
            if ((Test-Path $localBin) -and ($env:PATH -notmatch [Regex]::Escape($localBin))) {
                $env:PATH = "$localBin;$env:PATH"
            }

            $destroyResult = & terraform destroy -auto-approve 2>&1
            $destroyExit = $LASTEXITCODE

            if ($destroyExit -eq 0) {
                Write-Host '[OK]   terraform destroy succeeded' -ForegroundColor Green
            } else {
                Write-Host '[WARN] terraform destroy failed (resources may not exist)' -ForegroundColor Yellow
                Write-Host '       Continuing with Snowflake cleanup...' -ForegroundColor DarkGray
            }
        } finally {
            Pop-Location
        }
    } else {
        Write-Host "[1/3] No terraform.tfstate in labs\$labDirName — skipping terraform destroy" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[1/3] Lab directory labs\$labDirName does not exist yet" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------
# 2. Drop leftover Snowflake resources for this lab only
# ------------------------------------------------------------------

Write-Host ''
Write-Host "[2/3] Dropping leftover Snowflake resources for $Lab..." -ForegroundColor Yellow

# Build the list of resource names to drop based on the lab
# All labs use the pattern: {prefix}_{Lab}_{type}_{env}
$resourcesToDrop = @{
    # Databases
    "${LearnerPrefix}_${Lab}_RAW_${Environment}"           = "DATABASE"
    "${LearnerPrefix}_${Lab}_BROWNFIELD_${Environment}"    = "DATABASE"
    "DB_${LearnerPrefix}_${Lab}_BROWNFIELD_${Environment}" = "DATABASE"
    "${LearnerPrefix}_${Lab}_SALES_${Environment}"         = "DATABASE"
    "${LearnerPrefix}_${Lab}_FINANCE_${Environment}"       = "DATABASE"
    "${LearnerPrefix}SAL_${Lab}_RAW_${Environment}"        = "DATABASE"
    # Warehouses
    "WH_${LearnerPrefix}_${Lab}_ETL_${Environment}"        = "WAREHOUSE"
    "WH_${LearnerPrefix}SAL_${Lab}_ETL_${Environment}"     = "WAREHOUSE"
    "WH_${LearnerPrefix}_${Lab}_FINOPS_${Environment}"     = "WAREHOUSE"
}

foreach ($resource in $resourcesToDrop.Keys) {
    $type = $resourcesToDrop[$resource]
    $sql = "DROP ${type} IF EXISTS `"$resource`""
    $result = & snow sql -c training -q $sql 2>&1
    if ($LASTEXITCODE -eq 0 -and $result -notmatch 'does not exist|not found') {
        Write-Host "[OK]   Dropped ${type}: $resource" -ForegroundColor Green
    } else {
        Write-Host "[SKIP] ${type} not found: $resource" -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------
# 3. Clean local state files in the lab directory
# ------------------------------------------------------------------

Write-Host ''
Write-Host "[3/3] Cleaning local state files..." -ForegroundColor Yellow

if (Test-Path $labDir) {
    Push-Location $labDir
    try {
        $cleaned = @()
        foreach ($pattern in @('terraform.tfstate', 'terraform.tfstate.backup', '*.tfplan')) {
            Get-ChildItem -Path '.' -Filter $pattern -ErrorAction SilentlyContinue | ForEach-Object {
                Remove-Item $_.FullName -Force
                $cleaned += $_.Name
            }
        }
        if (Test-Path '.terraform') {
            Remove-Item '.terraform' -Recurse -Force -ErrorAction SilentlyContinue
            $cleaned += '.terraform/'
        }
        if (Test-Path '.terraform.lock.hcl') {
            Remove-Item '.terraform.lock.hcl' -Force -ErrorAction SilentlyContinue
            $cleaned += '.terraform.lock.hcl'
        }

        if ($cleaned.Count -gt 0) {
            foreach ($f in $cleaned) {
                Write-Host "[OK]   Removed: $f" -ForegroundColor Green
            }
        } else {
            Write-Host '[OK]   No state files to clean' -ForegroundColor DarkGray
        }
    } finally {
        Pop-Location
    }
} else {
    Write-Host '[OK]   Lab directory does not exist — nothing to clean' -ForegroundColor DarkGray
}

# ------------------------------------------------------------------
# Done
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Green
Write-Host " Lab $Lab reset complete" -ForegroundColor Green
Write-Host '============================================================' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  cd labs\$labDirName" -ForegroundColor DarkGray
Write-Host '  terraform init' -ForegroundColor DarkGray
Write-Host '  terraform plan' -ForegroundColor DarkGray
Write-Host ''
