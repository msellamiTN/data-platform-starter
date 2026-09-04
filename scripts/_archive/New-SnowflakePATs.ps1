#requires -version 5.1
<#
.SYNOPSIS
    Automatise la création de l'utilisateur Snowflake service et de son PAT/JWT.

.DESCRIPTION
    Prérequis : le compte admin (DATA2AI) est déjà connecté via snow en PAT ou JWT.
    Ce script est appelé par Setup-Day0.ps1.

    Étapes :
      1. Charger .env
      2. Vérifier la connexion admin
      3. Créer la network policy TRAINING_POLICY
      4. Créer TERRAFORM_SVC
      5. Mode PAT  : créer un PAT pour TERRAFORM_SVC, sauvegarder le token
      6. Mode JWT  : générer une clé RSA, assigner la clé publique à TERRAFORM_SVC
      7. Configurer la connexion snow terraform_svc

.PARAMETER AuthMode
    Mode d'authentification : PAT (défaut) ou JWT.

.EXAMPLE
    .\scripts\New-SnowflakePATs.ps1

.EXAMPLE
    .\scripts\New-SnowflakePATs.ps1 -AuthMode JWT
#>

[CmdletBinding()]
param(
    [ValidateSet("PAT", "JWT")]
    [string]$AuthMode = "PAT"
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
function Write-Warn   { param([string]$Message) Write-Host "[WARN] $Message" -ForegroundColor Magenta }

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

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-RepoRoot {
    return (Resolve-Path "$PSScriptRoot\..").Path
}

function Invoke-SnowSql {
    param(
        [string]$Connection,
        [string]$Query
    )
    return & snow sql -c $Connection -q $Query 2>&1
}

function Get-SnowflakeHost {
    $org = $env:SNOWFLAKE_ORGANIZATION
    $acct = $env:SNOWFLAKE_ACCOUNT
    return "$org-$acct.snowflakecomputing.com"
}

# ============================================================
# ÉTAPE 1 : charger .env
# ============================================================

Write-Step 1 6 "Chargement de .env"

$repoRoot = Get-RepoRoot
$envFile = Join-Path $repoRoot ".env"
Import-DotEnv -Path $envFile
Write-Ok ".env chargé"

# ============================================================
# ÉTAPE 2 : vérifier la connexion admin
# ============================================================

Write-Step 2 6 "Vérification connexion admin Snowflake"

if (-not (Test-CommandExists "snow")) {
    throw "Snowflake CLI (snow) n'est pas disponible."
}

$adminConnection = $env:SNOWFLAKE_ADMIN_CONNECTION
if ([string]::IsNullOrWhiteSpace($adminConnection)) { $adminConnection = "admin" }

Write-Info "Test de connexion admin '$adminConnection' ..."
$snowTest = & snow connection test -c $adminConnection 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err ($snowTest -join "`n")
    throw "Connexion admin '$adminConnection' invalide."
}
Write-Ok "Connexion admin OK"

# ============================================================
# ÉTAPE 3 : network policy
# ============================================================

Write-Step 3 6 "Création de la network policy"

$allowedIps = $env:TRAINING_NETWORK_ALLOWED_IPS
if ([string]::IsNullOrWhiteSpace($allowedIps)) { $allowedIps = "0.0.0.0/0" }

$policyQuery = @"
CREATE NETWORK POLICY IF NOT EXISTS TRAINING_POLICY
  ALLOWED_IP_LIST = ('$allowedIps');

ALTER ACCOUNT SET NETWORK_POLICY = TRAINING_POLICY;
"@

$policyResult = Invoke-SnowSql -Connection $adminConnection -Query $policyQuery
if ($LASTEXITCODE -ne 0) {
    Write-Err ($policyResult -join "`n")
    throw "Échec de création de la network policy."
}
Write-Ok "Network policy TRAINING_POLICY configurée avec $allowedIps"

# ============================================================
# ÉTAPE 4 : créer TERRAFORM_SVC
# ============================================================

Write-Step 4 6 "Création de l'utilisateur TERRAFORM_SVC"

$terraformUser = $env:SNOWFLAKE_TERRAFORM_USER
$role = $env:SNOWFLAKE_ROLE

$createUserQuery = @"
CREATE USER IF NOT EXISTS $terraformUser
  TYPE = SERVICE
  DEFAULT_ROLE = $role;

GRANT ROLE $role TO USER $terraformUser;
"@

$createResult = Invoke-SnowSql -Connection $adminConnection -Query $createUserQuery
if ($LASTEXITCODE -ne 0) {
    Write-Err ($createResult -join "`n")
    throw "Échec de création de $terraformUser."
}
Write-Ok "Utilisateur $terraformUser créé / existant"

# ============================================================
# ÉTAPE 5 — Créer le credential PAT ou JWT
# ============================================================

$secretsDir = Join-Path $repoRoot "secrets"
if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    Write-Info "Dossier secrets/ créé"
}

if ($AuthMode -eq "PAT") {
    Write-Step 5 6 "Création du PAT pour TERRAFORM_SVC"

    $terraformPatFile = Join-Path $repoRoot $env:SNOWFLAKE_TERRAFORM_PAT_FILE
    $terraformPatToken = ""

    if (Test-Path $terraformPatFile) {
        $terraformPatToken = Get-Content $terraformPatFile -Raw
        Write-Ok "PAT TERRAFORM_SVC déjà présent dans $terraformPatFile"
    } else {
        Write-Info "Création du PAT terraform_pat pour $terraformUser ..."
        $patQuery = "ALTER USER $terraformUser ADD PROGRAMMATIC ACCESS TOKEN terraform_pat DAYS_TO_EXPIRY = 90;"
        $patResult = Invoke-SnowSql -Connection $adminConnection -Query $patQuery

        if ($LASTEXITCODE -ne 0) {
            Write-Err ($patResult -join "`n")
            throw "Échec de création du PAT pour $terraformUser."
        }

        # Tenter d'extraire le token de la sortie
        $patResultString = $patResult -join " "
        # Patterns courants : token peut être dans la sortie brute
        if ($patResultString -match '([A-Za-z0-9_\-]{100,})') {
            $terraformPatToken = $matches[1]
            Write-Ok "Token extrait automatiquement de la sortie snow"
        } else {
            Write-Warn "Le token n'a pas pu être extrait automatiquement."
            Write-Warn "Allez dans Snowsight → Users → $terraformUser → Programmatic Access Tokens,"
            Write-Warn "copiez le token terraform_pat et collez-le ci-dessous."
            $terraformPatToken = Read-Host -Prompt "Token terraform_pat"
        }

        if ([string]::IsNullOrWhiteSpace($terraformPatToken)) {
            throw "Token terraform_pat vide."
        }

        $terraformPatToken | Set-Content -Path $terraformPatFile -NoNewline
        Write-Ok "PAT sauvegardé dans $terraformPatFile"
    }

    # Configurer la connexion snow terraform_svc en PAT
    $terraformConnection = $env:SNOWFLAKE_TERRAFORM_CONNECTION
    if ([string]::IsNullOrWhiteSpace($terraformConnection)) { $terraformConnection = "terraform_svc" }

    & snow connection remove $terraformConnection 2>&1 | Out-Null

    $account = $env:SNOWFLAKE_ACCOUNT
    $host = Get-SnowflakeHost
    $user = $env:SNOWFLAKE_TERRAFORM_USER

    & snow connection add -n $terraformConnection `
        -a $account `
        -h $host `
        -u $user `
        -r $role `
        -A "PROGRAMMATIC_ACCESS_TOKEN" `
        -t "$terraformPatFile" `
        --no-interactive

    if ($LASTEXITCODE -ne 0) {
        throw "Échec de l'ajout de la connexion snow terraform_svc (PAT)."
    }
    Write-Ok "Connexion snow '$terraformConnection' configurée (PAT)"

} else {
    Write-Step 5 6 "Génération de la clé JWT pour TERRAFORM_SVC"

    $openssl = Get-Command openssl -ErrorAction SilentlyContinue
    if (-not $openssl) {
        $gitOpenssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
        if (Test-Path $gitOpenssl) {
            $env:PATH = "C:\Program Files\Git\mingw64\bin;$env:PATH"
            $openssl = Get-Command openssl -ErrorAction SilentlyContinue
        }
    }
    if (-not $openssl) {
        throw "OpenSSL non trouvé. Installez Git ou OpenSSL."
    }

    $keyPath = Join-Path $repoRoot $env:SNOWFLAKE_PRIVATE_KEY_FILE
    $pubPath = [System.IO.Path]::ChangeExtension($keyPath, ".pub")
    $onelinePath = [System.IO.Path]::ChangeExtension($keyPath, ".oneline")

    if (-not (Test-Path $keyPath)) {
        Write-Info "Génération de la paire de clés RSA..."
        & openssl genrsa 2048 | & openssl pkcs8 -topk8 -inform PEM -out $keyPath -nocrypt
        & openssl rsa -in $keyPath -pubout -out $pubPath
        (Get-Content $pubPath | Where-Object { $_ -notmatch 'BEGIN|END' }) -join '' | Set-Content $onelinePath -NoNewline
        Write-Ok "Clés RSA générées : $keyPath"
    } else {
        Write-Ok "Clé RSA existante : $keyPath"
    }

    $pubKey = (Get-Content $pubPath | Where-Object { $_ -notmatch 'BEGIN|END' }) -join ''

    $assignQuery = @"
ALTER USER $terraformUser SET RSA_PUBLIC_KEY = '$pubKey';
"@
    $assignResult = Invoke-SnowSql -Connection $adminConnection -Query $assignQuery
    if ($LASTEXITCODE -ne 0) {
        Write-Err ($assignResult -join "`n")
        throw "Échec d'assignation de la clé publique à $terraformUser."
    }
    Write-Ok "Clé publique assignée à $terraformUser"

    # Configurer la connexion snow terraform_svc en JWT
    $terraformConnection = $env:SNOWFLAKE_TERRAFORM_CONNECTION
    if ([string]::IsNullOrWhiteSpace($terraformConnection)) { $terraformConnection = "terraform_svc" }

    & snow connection remove $terraformConnection 2>&1 | Out-Null

    $account = $env:SNOWFLAKE_ACCOUNT
    $host = Get-SnowflakeHost
    $user = $env:SNOWFLAKE_TERRAFORM_USER

    & snow connection add -n $terraformConnection `
        -a $account `
        -h $host `
        -u $user `
        -r $role `
        -A "SNOWFLAKE_JWT" `
        -k "$keyPath" `
        --no-interactive

    if ($LASTEXITCODE -ne 0) {
        throw "Échec de l'ajout de la connexion snow terraform_svc (JWT)."
    }
    Write-Ok "Connexion snow '$terraformConnection' configurée (JWT)"
}

# ============================================================
# ÉTAPE 6 — Vérifier la connexion terraform_svc
# ============================================================

Write-Step 6 6 "Test de la connexion terraform_svc"

$tfConnection = $env:SNOWFLAKE_TERRAFORM_CONNECTION
if ([string]::IsNullOrWhiteSpace($tfConnection)) { $tfConnection = "terraform_svc" }

$tfTest = & snow connection test -c $tfConnection 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Err ($tfTest -join "`n")
    throw "Connexion terraform_svc invalide."
}
Write-Ok "Connexion terraform_svc OK"

$currentUser = & snow sql -c $tfConnection -q "SELECT CURRENT_USER()" 2>&1 | Select-String "TERRAFORM_SVC"
if ($LASTEXITCODE -eq 0) {
    Write-Ok "Utilisateur courant confirmé : TERRAFORM_SVC"
} else {
    Write-Warn "Impossible de confirmer CURRENT_USER()."
}

Write-Host ""
Write-Ok "New-SnowflakePATs.ps1 terminé avec succès (mode $AuthMode)."
