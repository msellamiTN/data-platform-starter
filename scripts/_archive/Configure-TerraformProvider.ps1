#requires -version 5.1
<#
.SYNOPSIS
    Génère le fichier terraform.tfvars pour le projet M1 à partir de .env.

.DESCRIPTION
    Ce script lit .env et crée ou met à jour terraform.tfvars dans
    project/01-day1-basics. Supporte les modes PAT et JWT.

.PARAMETER AuthMode
    Mode d'authentification : PAT (défaut) ou JWT.

.PARAMETER Project
    Chemin du projet Terraform. Défaut : project\01-day1-basics

.EXAMPLE
    .\scripts\Configure-TerraformProvider.ps1

.EXAMPLE
    .\scripts\Configure-TerraformProvider.ps1 -AuthMode JWT -Project project\01-day1-basics
#>

[CmdletBinding()]
param(
    [ValidateSet("PAT", "JWT")]
    [string]$AuthMode = "PAT",
    [string]$Project = "project\01-day1-basics"
)

$ErrorActionPreference = "Stop"

# ============================================================
# HELPERS
# ============================================================

function Write-Step {
    param([int]$Number, [int]$Total, [string]$Name)
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Number/$Total - $Name" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Write-Ok     { param([string]$Message) Write-Host "[OK] $Message" -ForegroundColor Green }
function Write-Err    { param([string]$Message) Write-Host "[ERROR] $Message" -ForegroundColor Red }
function Write-Info   { param([string]$Message) Write-Host "[INFO] $Message" -ForegroundColor Yellow }

function Import-DotEnv {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "Fichier .env manquant : $Path"
    }
    Get-Content $Path | ForEach-Object {
        $line = $_.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line.StartsWith("#")) { return }
        if ($line -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $name = $matches[1]
            $value = $matches[2]
            if ($value -match '^"(.*)"$' -or $value -match "^'(.*)'$") {
                $value = $matches[1]
            }
            [Environment]::SetEnvironmentVariable($name, $value, "Process")
        }
    }
}

# ============================================================
# ÉTAPE 1 : charger .env
# ============================================================

Write-Step 1 3 "Chargement de .env"

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$envFile = Join-Path $repoRoot ".env"
Import-DotEnv -Path $envFile
Write-Ok ".env chargé"

# ============================================================
# ÉTAPE 2 : construire le contenu de terraform.tfvars
# ============================================================

Write-Step 2 3 "Génération de terraform.tfvars"

$projectDir = Join-Path $repoRoot $Project
if (-not (Test-Path $projectDir)) {
    throw "Projet introuvable : $projectDir"
}

$tfvarsPath = Join-Path $projectDir "terraform.tfvars"

$org = $env:SNOWFLAKE_ORGANIZATION
$acct = $env:SNOWFLAKE_ACCOUNT
$user = $env:SNOWFLAKE_TERRAFORM_USER
$role = $env:SNOWFLAKE_ROLE
$environment = $env:ENVIRONMENT
$team = $env:TEAM

$tfvarsContent = @"
# Généré automatiquement par Configure-TerraformProvider.ps1
# Ne modifiez pas manuellement — mettez à jour .env et relancez le script.

snowflake_organization_name = "$org"
snowflake_account_name      = "$acct"
snowflake_user              = "$user"
snowflake_role              = "$role"
environment                 = "$environment"
team                        = "$team"
"@

if ($AuthMode -eq "PAT") {
    $patFile = Join-Path $repoRoot $env:SNOWFLAKE_TERRAFORM_PAT_FILE
    if (-not (Test-Path $patFile)) {
        throw "Fichier PAT TERRAFORM_SVC introuvable : $patFile. Exécutez New-SnowflakePATs.ps1."
    }

    # Chemin relatif depuis le projet vers le fichier PAT
    $patRelative = [System.IO.Path]::GetFullPath($patFile).Replace([System.IO.Path]::GetFullPath($repoRoot), "").TrimStart("\", "/")

    $tfvarsContent += @"

# Authentification PAT (Programmatic Access Token)
snowflake_authenticator = "programmatic_access_token"
snowflake_token_file_path = "../../$patRelative"
"@
    Write-Info "Mode PAT : token file path = $patFile"
} else {
    $keyFile = Join-Path $repoRoot $env:SNOWFLAKE_PRIVATE_KEY_FILE
    if (-not (Test-Path $keyFile)) {
        throw "Fichier de clé privée JWT introuvable : $keyFile. Exécutez New-SnowflakePATs.ps1."
    }

    $tfvarsContent += @"

# Authentification JWT (key-pair)
snowflake_authenticator  = "JWT"
snowflake_private_key_path = "$env:SNOWFLAKE_PRIVATE_KEY_FILE"
"@
    Write-Info "Mode JWT : clé privée = $keyFile"
}

# Écrire le fichier
$tfvarsContent | Set-Content -Path $tfvarsPath -Encoding UTF8 -NoNewline
Write-Ok "terraform.tfvars créé : $tfvarsPath"

# ============================================================
# ÉTAPE 3 : vérifier la syntaxe
# ============================================================

Write-Step 3 3 "Vérification de terraform.tfvars"

Push-Location $projectDir
try {
    $validate = & terraform validate -var-file $tfvarsPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Err ($validate -join "`n")
        throw "terraform validate a échoué avec terraform.tfvars."
    }
    Write-Ok "terraform.tfvars valide"
} finally {
    Pop-Location
}
