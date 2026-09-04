#requires -version 5.1
<#
.SYNOPSIS
    Installe et vérifie tous les outils requis pour la formation Terraform & Snowflake.
.DESCRIPTION
    Script idempotent : si un outil est déjà installé à la bonne version, il est ignoré.
    À la fin, affiche un tableau récapitulatif et crée les fichiers/dossiers de base.
.EXAMPLE
    .\scripts\Install-LabEnvironment.ps1
#>

[CmdletBinding()]
param(
    [string]$TerraformVersion = "1.14.5",
    [string]$InstallDir = "C:\tools\tf-bin"
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Status($name, $ok, $detail) {
    $icon = if ($ok) { "✅" } else { "❌" }
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host "  $icon $name — $detail" -ForegroundColor $color
}

function Test-CommandExists($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

function Add-ToUserPath($dir) {
    $currentPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if ($currentPath -notlike "*$dir*") {
        [Environment]::SetEnvironmentVariable('PATH', "$dir;$currentPath", 'User')
        Write-Host "  📌 Ajouté au PATH utilisateur : $dir" -ForegroundColor Cyan
    }
}

# ── Results tracking ─────────────────────────────────────────────────────────
$results = @()

# ── 1. Terraform ─────────────────────────────────────────────────────────────

Write-Host "`n── 1/6 — Terraform $TerraformVersion ──" -ForegroundColor Cyan

$tfOk = $false
if (Test-CommandExists 'terraform') {
    $ver = & terraform version 2>&1 | Select-Object -First 1
    if ($ver -match $TerraformVersion) {
        Write-Status "Terraform" $true "v$TerraformVersion détecté"
        $tfOk = $true
    } else {
        Write-Status "Terraform" $false "Version incorrecte: $ver (attendu $TerraformVersion)"
    }
} else {
    Write-Host "  ⬇️  Téléchargement de Terraform $TerraformVersion..." -ForegroundColor Yellow
    $url = "https://releases.hashicorp.com/terraform/$TerraformVersion/terraform_${TerraformVersion}_windows_amd64.zip"
    $zip = Join-Path $env:TEMP "terraform_${TerraformVersion}.zip"
    try {
        Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
        if (-not (Test-Path $InstallDir)) { New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null }
        Expand-Archive -Path $zip -DestinationPath $InstallDir -Force
        Remove-Item $zip -Force
        Add-ToUserPath $InstallDir
        $env:PATH = "$InstallDir;$env:PATH"
        $ver = & terraform version 2>&1 | Select-Object -First 1
        Write-Status "Terraform" $true "Installé — $ver"
        $tfOk = $true
    } catch {
        Write-Status "Terraform" $false "Échec du téléchargement: $($_.Exception.Message)"
    }
}
$results += [PSCustomObject]@{ Tool = "Terraform"; Ok = $tfOk }

# ── 2. Snowflake CLI ─────────────────────────────────────────────────────────

Write-Host "`n── 2/6 — Snowflake CLI ──" -ForegroundColor Cyan

$snowOk = $false
if (Test-CommandExists 'snow') {
    $ver = & snow --version 2>&1
    Write-Status "Snowflake CLI" $true "$ver"
    $snowOk = $true
} else {
    Write-Host "  ⬇️  Installation via pip..." -ForegroundColor Yellow
    if (Test-CommandExists 'python') {
        try {
            & python -m pip install snowflake-cli 2>&1 | Out-Null
            $ver = & snow --version 2>&1
            Write-Status "Snowflake CLI" $true "Installé — $ver"
            $snowOk = $true
        } catch {
            Write-Status "Snowflake CLI" $false "Échec pip: $($_.Exception.Message)"
        }
    } else {
        Write-Status "Snowflake CLI" $false "Python non trouvé. Installez Python 3.12/3.13 ou utilisez l'installeur officiel: https://developers.snowflake.com/snowflake-cli/"
    }
}
$results += [PSCustomObject]@{ Tool = "Snowflake CLI"; Ok = $snowOk }

# ── 3. Git ───────────────────────────────────────────────────────────────────

Write-Host "`n── 3/6 — Git ──" -ForegroundColor Cyan

$gitOk = $false
if (Test-CommandExists 'git') {
    $ver = & git --version 2>&1
    Write-Status "Git" $true "$ver"
    $gitOk = $true
} else {
    Write-Status "Git" $false "Non installé. Téléchargez: https://git-scm.com/download/win"
}
$results += [PSCustomObject]@{ Tool = "Git"; Ok = $gitOk }

# ── 4. OpenSSL ───────────────────────────────────────────────────────────────

Write-Host "`n── 4/6 — OpenSSL ──" -ForegroundColor Cyan

$sslOk = $false
$openssl = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $openssl) {
    $gitOpenssl = "C:\Program Files\Git\mingw64\bin\openssl.exe"
    if (Test-Path $gitOpenssl) {
        $env:PATH = "C:\Program Files\Git\mingw64\bin;$env:PATH"
        $openssl = $true
    }
}
if ($openssl) {
    $ver = & openssl version 2>&1
    Write-Status "OpenSSL" $true "$ver"
    $sslOk = $true
} else {
    Write-Status "OpenSSL" $false "Non trouvé. Installez Git (inclut OpenSSL) ou ajoutez C:\Program Files\Git\mingw64\bin au PATH"
}
$results += [PSCustomObject]@{ Tool = "OpenSSL"; Ok = $sslOk }

# ── 5. VS Code ───────────────────────────────────────────────────────────────

Write-Host "`n── 5/6 — VS Code ──" -ForegroundColor Cyan

$codeOk = $false
if (Test-CommandExists 'code') {
    $ver = & code --version 2>&1 | Select-Object -First 1
    Write-Status "VS Code" $true "$ver"
    $codeOk = $true
} else {
    Write-Status "VS Code" $false "Non installé. Téléchargez: https://code.visualstudio.com/"
}
$results += [PSCustomObject]@{ Tool = "VS Code"; Ok = $codeOk }

# ── 6. Azure CLI ─────────────────────────────────────────────────────────────

Write-Host "`n── 6/6 — Azure CLI ──" -ForegroundColor Cyan

$azOk = $false
if (Test-CommandExists 'az') {
    $ver = (& az version 2>&1 | ConvertFrom-Json).'azure-cli'
    Write-Status "Azure CLI" $true "v$ver"
    $azOk = $true
} else {
    Write-Status "Azure CLI" $false "Non installé. Téléchargez: https://aka.ms/installazurecliwindows"
}
$results += [PSCustomObject]@{ Tool = "Azure CLI"; Ok = $azOk }

# ── Post-install : secrets/ et .env ──────────────────────────────────────────

Write-Host "`n── Post-install — Structure de base ──" -ForegroundColor Cyan

$secretsDir = Join-Path $repoRoot 'secrets'
if (-not (Test-Path $secretsDir)) {
    New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    Write-Status "secrets/" $true "Dossier créé"
} else {
    Write-Status "secrets/" $true "Dossier existant"
}

$envExample = Join-Path $repoRoot '.env.example'
$envFile = Join-Path $repoRoot '.env'
if ((Test-Path $envExample) -and -not (Test-Path $envFile)) {
    Copy-Item $envExample $envFile
    Write-Status ".env" $true "Créé depuis .env.example (à éditer avec vos identifiants)"
} elseif (Test-Path $envFile) {
    Write-Status ".env" $true "Existant"
} else {
    Write-Status ".env" $false ".env.example introuvable — créez .env manuellement"
}

# ── Résumé ───────────────────────────────────────────────────────────────────

Write-Host "`n═══════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RÉSUMÉ DE L'INSTALLATION" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════" -ForegroundColor Cyan

$allOk = $true
foreach ($r in $results) {
    $icon = if ($r.Ok) { "✅" } else { "❌" }
    Write-Host "  $icon $($r.Tool)"
    if (-not $r.Ok) { $allOk = $false }
}

Write-Host ""
if ($allOk) {
    Write-Host "Tous les outils obligatoires sont installés. Vous pouvez commencer le Module 0." -ForegroundColor Green
    Write-Host "   Ouvrez : code `"$repoRoot\student-track\module-00-environment\module.md`"" -ForegroundColor Green
} else {
    $failed = $results | Where-Object { -not $_.Ok }
    Write-Host "⚠️  $($failed.Count) outil(s) à installer manuellement :" -ForegroundColor Yellow
    foreach ($f in $failed) {
        Write-Host "     — $($f.Tool)" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "   ⚠️  Fermez et rouvrez PowerShell après installation pour rafraîchir le PATH." -ForegroundColor Yellow
}

Write-Host ""
