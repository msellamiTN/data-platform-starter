# ============================================================
# bootstrap-vm.ps1 — Runs as SYSTEM via Run Command
# Template variables injected by Terraform templatefile():
#   ${learner_prefix}         e.g. APP01
#   ${repo_url}               e.g. https://github.com/msellamiTN/data-platform-starter.git
#   ${repo_local_path}        e.g. C:\Data2AI-Labs\data-platform
#   ${install_root}           e.g. C:\data2ai
#   shared_env_content      multi-line content for config/shared.env (injected)
#   ${key_vault_name}         e.g. kvdata2aitfsecretsmsn
#   ${snowflake_organization} e.g. ZVFXOZW
#   ${snowflake_account}      e.g. PM71247
#   ${snowflake_user}         e.g. DATA2AI
#   ${snowflake_role}         e.g. SYSADMIN
# ============================================================

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

$learnerPrefix  = '${learner_prefix}'
$repoUrl        = '${repo_url}'
$repoPath       = '${repo_local_path}'
$installRoot    = '${install_root}'
$kvName         = '${key_vault_name}'
$sfOrg          = '${snowflake_organization}'
$sfAccount      = '${snowflake_account}'
$sfUser         = '${snowflake_user}'
$sfRole         = '${snowflake_role}'

Write-Host "=== bootstrap-vm.ps1 -- Learner $learnerPrefix ===" -ForegroundColor Cyan

# ------------------------------------------------------------------
# 0. Install git (not pre-installed on Windows 11)
# ------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host "Installing git..." -ForegroundColor Green
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    # Try winget first (Windows 11 has it pre-installed)
    $wingetExit = 1
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $wingetResult = & winget install --id Git.Git --accept-package-agreements --accept-source-agreements --silent 2>&1
        $wingetExit = $LASTEXITCODE
    }
    $ErrorActionPreference = $prevEAP

    if ($wingetExit -ne 0) {
        Write-Host "winget failed (exit $wingetExit), trying direct installer..." -ForegroundColor Yellow
        $gitUrl = 'https://github.com/git-for-windows/git/releases/download/v2.47.1.windows.1/Git-2.47.1-64-bit.exe'
        $gitInstaller = "$env:TEMP\GitInstaller.exe"
        Invoke-WebRequest -Uri $gitUrl -OutFile $gitInstaller -UseBasicParsing
        Start-Process -FilePath $gitInstaller -ArgumentList '/VERYSILENT', '/NORESTART', '/NOCANCEL', '/SP-', '/CLOSEAPPLICATIONS' -Wait -NoNewWindow
        Remove-Item $gitInstaller -Force -ErrorAction SilentlyContinue
    }

    # Refresh PATH for this session
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "git is not available after installation attempt"
}
Write-Host "[PASS] git is available" -ForegroundColor Green

# ------------------------------------------------------------------
# 1. Clone the starter repo (idempotent)
# ------------------------------------------------------------------
$repoParent = Split-Path -Parent $repoPath
if (-not (Test-Path $repoParent)) {
    New-Item -ItemType Directory -Path $repoParent -Force | Out-Null
}

if (Test-Path "$repoPath\.git") {
    Write-Host "Repo already exists at $repoPath -- pulling latest..." -ForegroundColor Yellow
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $repoPath
    git pull --ff-only 2>&1 | Out-Host
    Pop-Location
    $ErrorActionPreference = $prevEAP
} else {
    Write-Host "Cloning $repoUrl -> $repoPath ..." -ForegroundColor Green
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    git clone $repoUrl $repoPath 2>&1 | Out-Host
    $ErrorActionPreference = $prevEAP
}

# ------------------------------------------------------------------
# 2. Install tools machine-wide (Install-Tools.ps1 -InstallRoot)
#    Using a fixed machine path (not $HOME) because Custom Script
#    Extension runs as SYSTEM — $HOME would be C:\Windows\System32.
# ------------------------------------------------------------------
Write-Host "Installing tools to $installRoot ..." -ForegroundColor Green
Push-Location $repoPath
& .\scripts\Install-Tools.ps1 -InstallRoot $installRoot -Force 2>&1 | Out-Host
Pop-Location

# Ensure machine PATH includes the install root bin + venv Scripts
$binDir     = Join-Path $installRoot 'bin'
$venvDir    = Join-Path $installRoot 'venv\Scripts'
$dbtVenvDir = Join-Path $installRoot 'venv-dbt\Scripts'

$machinePath = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
foreach ($dir in @($binDir, $venvDir, $dbtVenvDir)) {
    if ((Test-Path $dir) -and ($machinePath -notlike "*$dir*")) {
        $machinePath = "$dir;$machinePath"
    }
}
[Environment]::SetEnvironmentVariable('PATH', $machinePath, 'Machine')
Write-Host "Machine PATH updated." -ForegroundColor Green

# ------------------------------------------------------------------
# 3. Write config/shared.env (committed config, no secrets)
# ------------------------------------------------------------------
$configDir = Join-Path $repoPath 'config'
if (-not (Test-Path $configDir)) {
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
}
$sharedEnvPath = Join-Path $configDir 'shared.env'
$sharedEnvContent = @'
${shared_env_content}
'@
Set-Content -Path $sharedEnvPath -Value $sharedEnvContent -Encoding UTF8 -Force
Write-Host "config/shared.env written." -ForegroundColor Green

# ------------------------------------------------------------------
# 4. Create .env with LEARNER_PREFIX (no secrets — just the prefix)
# ------------------------------------------------------------------
$envPath = Join-Path $repoPath '.env'
$envContent = @"
LEARNER_PREFIX=$learnerPrefix
ENVIRONMENT=dev
"@
Set-Content -Path $envPath -Value $envContent -Encoding UTF8 -Force
Write-Host ".env written with LEARNER_PREFIX=$learnerPrefix" -ForegroundColor Green

# ------------------------------------------------------------------
# 5. Fetch secrets from Key Vault using managed identity (no browser login)
#    The VM's system-assigned MI has been granted Key Vault Secrets User.
#    We login with --identity, fetch SP creds + Snowflake PAT, and write
#    them to secrets/ files so Learner-Login.ps1 works in fallback if MI fails.
# ------------------------------------------------------------------
Write-Host "Fetching secrets from Key Vault via managed identity..." -ForegroundColor Green

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$miLogin = & az login --identity --output none 2>&1
$miLoginExit = $LASTEXITCODE
$ErrorActionPreference = $prevEAP

if ($miLoginExit -ne 0) {
    Write-Host "[WARN] Managed identity login failed. Secrets will need manual setup." -ForegroundColor Yellow
    Write-Host "       $miLogin" -ForegroundColor DarkGray
} else {
    Write-Host "[PASS] Managed identity login successful" -ForegroundColor Green

    # Fetch SP credentials + PAT from Key Vault
    $armClientId     = & az keyvault secret show --vault-name $kvName --name ArmClientId --query value -o tsv 2>$null
    $armClientSecret = & az keyvault secret show --vault-name $kvName --name ArmClientSecret --query value -o tsv 2>$null
    $armTenantId     = & az keyvault secret show --vault-name $kvName --name ArmTenantId --query value -o tsv 2>$null
    $armSubId        = & az keyvault secret show --vault-name $kvName --name ArmSubscriptionId --query value -o tsv 2>$null
    $snowflakePat    = & az keyvault secret show --vault-name $kvName --name SnowflakePAT --query value -o tsv 2>$null

    # Write secrets/shared-sp.txt
    $secretsDir = Join-Path $repoPath 'secrets'
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    }
    $sharedSpFile = Join-Path $secretsDir 'shared-sp.txt'
    if ($armClientId -and $armClientSecret -and $armTenantId -and $armSubId) {
        $spContent = @(
            "# Auto-generated by bootstrap-vm.ps1 (managed identity)"
            "# DO NOT COMMIT - this file is gitignored."
            "ARM_CLIENT_ID=$armClientId"
            "ARM_CLIENT_SECRET=$armClientSecret"
            "ARM_TENANT_ID=$armTenantId"
            "ARM_SUBSCRIPTION_ID=$armSubId"
        ) -join "`r`n"
        [System.IO.File]::WriteAllText($sharedSpFile, $spContent, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[PASS] SP credentials written to secrets/shared-sp.txt" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Could not fetch all SP credentials from Key Vault" -ForegroundColor Yellow
    }

    # Write secrets/snowflake_pat.txt
    $patFile = Join-Path $secretsDir 'snowflake_pat.txt'
    if ($snowflakePat) {
        [System.IO.File]::WriteAllText($patFile, $snowflakePat, [System.Text.UTF8Encoding]::new($false))
        Write-Host "[PASS] Snowflake PAT written to secrets/snowflake_pat.txt" -ForegroundColor Green
    } else {
        Write-Host "[WARN] Could not fetch SnowflakePAT from Key Vault" -ForegroundColor Yellow
    }

    # Logout MI session so it doesn't interfere with learner's az login later
    & az logout 2>&1 | Out-Null

    # ------------------------------------------------------------------
    # 5b. Pre-configure Snow CLI config.toml for the admin user
    #     so 'snow sql -c training' works without running New-SnowflakeConnection.ps1
    # ------------------------------------------------------------------
    $idx = [int]($learnerPrefix -replace 'APP','')
    $adminUser = 'apprenant' + $idx.ToString('00')
    $userProfile = "C:\Users\$adminUser"

    $snowflakeConfigDir = Join-Path $userProfile '.snowflake'
    if (-not (Test-Path $snowflakeConfigDir)) {
        New-Item -ItemType Directory -Path $snowflakeConfigDir -Force | Out-Null
    }
    $snowflakeConfigFile = Join-Path $snowflakeConfigDir 'config.toml'

    $hostValue = "$sfOrg-$sfAccount.snowflakecomputing.com"
    $patFilePathTOML = $patFile -replace '\\', '/'

    $configLines = @(
        "[connections.training]"
        "account = `"$sfAccount`""
        "user = `"$sfUser`""
        "role = `"$sfRole`""
        "authenticator = `"PROGRAMMATIC_ACCESS_TOKEN`""
        "token_file_path = `"$patFilePathTOML`""
        "host = `"$hostValue`""
    )
    [System.IO.File]::WriteAllLines($snowflakeConfigFile, $configLines, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[PASS] Snow CLI config.toml written to $snowflakeConfigFile" -ForegroundColor Green

    # Set file permissions for the admin user
    if (Test-Path $patFile) {
        & icacls $patFile /inheritance:r 2>&1 | Out-Null
        & icacls $patFile /grant:r "$${adminUser}:(F)" 2>&1 | Out-Null
        & icacls $patFile /grant:r "SYSTEM:(F)" 2>&1 | Out-Null
    }
    if (Test-Path $snowflakeConfigFile) {
        & icacls $snowflakeConfigFile /inheritance:r 2>&1 | Out-Null
        & icacls $snowflakeConfigFile /grant:r "$${adminUser}:(F)" 2>&1 | Out-Null
    }
    if (Test-Path $sharedSpFile) {
        & icacls $sharedSpFile /inheritance:r 2>&1 | Out-Null
        & icacls $sharedSpFile /grant:r "$${adminUser}:(F)" 2>&1 | Out-Null
        & icacls $sharedSpFile /grant:r "SYSTEM:(F)" 2>&1 | Out-Null
    }
    Write-Host "[PASS] File permissions set for $adminUser" -ForegroundColor Green
}

# ------------------------------------------------------------------
# 6. Create first-logon script + shortcut in the admin user's Startup
#    folder. The admin username matches the Snowflake learner username
#    (e.g. apprenant01). This script runs at the first interactive
#    logon and launches Learner-Login (MI-first) + VS Code.
# ------------------------------------------------------------------
$adminUser = "apprenant$($learnerPrefix -replace 'APP','')"
$adminUser = $adminUser -replace '^apprenant0','apprenant'

# Build the actual zero-padded username matching the pattern
$idx = [int]($learnerPrefix -replace 'APP','')
$adminUser = 'apprenant' + $idx.ToString('00')

$userProfile = "C:\Users\$adminUser"
$startupDir  = "$userProfile\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"

# Create the user profile directory structure if it doesn't exist yet
if (-not (Test-Path $startupDir)) {
    New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
}

$firstLogonScript = Join-Path $repoPath 'scripts\first-logon.ps1'
$firstLogonContent = @"
# Auto-generated first-logon script for learner $learnerPrefix
# Runs Learner-Login.ps1 then opens VS Code
`$ErrorActionPreference = 'Continue'
Set-Location '$repoPath'
Write-Host '=== Bienvenue apprenant $learnerPrefix ===' -ForegroundColor Cyan
Write-Host 'Lancement de Learner-Login.ps1...' -ForegroundColor Green
& '.\scripts\Learner-Login.ps1' -LearnerPrefix '$learnerPrefix'
Write-Host ''
Write-Host 'Verification de la readiness de la VM...' -ForegroundColor Green
if (Test-Path '.\scripts\Test-VMReadiness.ps1') {
    & '.\scripts\Test-VMReadiness.ps1' -LearnerPrefix '$learnerPrefix'
}
Write-Host ''
Write-Host 'Ouverture de VS Code...' -ForegroundColor Green
Start-Process 'code' -ArgumentList '$repoPath'
"@
Set-Content -Path $firstLogonScript -Value $firstLogonContent -Encoding UTF8 -Force

# Create a .bat launcher in Startup that calls the PowerShell script
$batLauncher = Join-Path $startupDir 'first-logon.bat'
$batContent = @"
@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$firstLogonScript"
"@
Set-Content -Path $batLauncher -Value $batContent -Encoding UTF8 -Force

Write-Host "First-logon script deployed to $startupDir" -ForegroundColor Green
Write-Host "=== bootstrap-vm.ps1 complete for $learnerPrefix ===" -ForegroundColor Cyan
