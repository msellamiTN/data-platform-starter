#requires -version 5.1
<#
.SYNOPSIS
    Creates individual Snowflake users for each learner.

.DESCRIPTION
    For each learner:
    - Creates a Snowflake user (apprenant01 to apprenant10)
    - Sets a password (14+ chars, compliant with Snowflake password policy)
    - Grants SYSADMIN role
    - The user can login to app.snowflake.com and use CLI

    Passwords are saved to secrets/learner-snowflake-passwords.txt (gitignored).

    Password policy (Snowflake Enterprise):
    - At least 14 characters
    - At least 1 digit
    - At least 1 uppercase letter
    - At least 1 lowercase letter

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER ResetPasswords
    Reset passwords for existing users (use if password policy changed).

.EXAMPLE
    .\scripts\Add-SnowflakeLearners.ps1
    .\scripts\Add-SnowflakeLearners.ps1 -DryRun
    .\scripts\Add-SnowflakeLearners.ps1 -ResetPasswords
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$ResetPasswords
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$secretsDir = Join-Path $projectRoot 'secrets'
$secretsFile = Join-Path $secretsDir 'learner-snowflake-passwords.txt'

# ------------------------------------------------------------------
# Verify Snowflake CLI connection
# ------------------------------------------------------------------

Write-Host '[INFO] Testing Snowflake connection...' -ForegroundColor DarkGray

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$testResult = & snow sql -c training -q "SELECT CURRENT_USER(), CURRENT_ROLE()" 2>&1
$ErrorActionPreference = $prevEAP

if ($LASTEXITCODE -ne 0) {
    Write-Host '[FAIL] Snowflake CLI connection failed' -ForegroundColor Red
    Write-Host '       Run New-SnowflakeConnection.ps1 first' -ForegroundColor DarkGray
    exit 1
}

Write-Host '[PASS] Snowflake connection OK' -ForegroundColor Green
Write-Host ''

# ------------------------------------------------------------------
# Learner list
# Passwords: 14+ chars, 1 digit, 1 uppercase, 1 lowercase
# Pattern: SnowflakeLearner2026@XX (24 chars, meets all requirements)
# ------------------------------------------------------------------

$learners = 1..10 | ForEach-Object {
    $padded = '{0:D2}' -f $_
    [PSCustomObject]@{
        Name     = "apprenant$padded"
        Password = "SnowflakeLearner2026@$padded"
        Login    = "apprenant$padded"
    }
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

$mode = if ($DryRun) { 'DRY RUN (no changes)' } else { 'PROVISION' }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Snowflake Learner Users - $mode" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Users: $($learners.Count)"
Write-Host " Role:  SYSADMIN"
Write-Host ''

# ------------------------------------------------------------------
# Create each user
# ------------------------------------------------------------------

$created = 0
$existing = 0
$failed = 0
$passwordLines = @()

$passwordLines += "# Snowflake Learner Passwords"
$passwordLines += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$passwordLines += "# Format: username|password"
$passwordLines += "# Web login: https://app.snowflake.com/<org>-<account>/login"
$passwordLines += ""

foreach ($l in $learners) {
    Write-Host "-- $($l.Name)" -ForegroundColor Cyan

    # Check if user exists (case-insensitive, match name column only)
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $checkResult = & snow sql -c training -q "SHOW USERS LIKE '$($l.Name)'" 2>&1
    $ErrorActionPreference = $prevEAP

    $checkText = $checkResult | Out-String
    $userExists = $checkText -match "(?im)^\|\s+$($l.Name)\s+\|"

    if ($userExists) {
        if ($ResetPasswords) {
            Write-Host "   [INFO] User exists, resetting password..." -ForegroundColor DarkGray
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $resetResult = & snow sql -c training -q "ALTER USER $($l.Name) SET PASSWORD='$($l.Password)'" 2>&1
            $resetExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            if ($resetExit -eq 0) {
                Write-Host "   [PASS] Password reset" -ForegroundColor Green
            } else {
                Write-Host "   [FAIL] Password reset failed" -ForegroundColor Red
                $failed++
            }
            $existing++
        } else {
            Write-Host "   [SKIP] User already exists (use -ResetPasswords to update)" -ForegroundColor Yellow
            $existing++
        }
    } elseif ($DryRun) {
        Write-Host "   [DRY] Would create user with SYSADMIN role" -ForegroundColor DarkGray
        $created++
    } else {
        # Create user with password
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $createResult = & snow sql -c training -q "CREATE USER $($l.Name) PASSWORD='$($l.Password)' DEFAULT_ROLE='SYSADMIN' MUST_CHANGE_PASSWORD=FALSE" 2>&1
        $createExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($createExit -eq 0) {
            Write-Host "   [PASS] User created" -ForegroundColor Green
            $created++
        } else {
            Write-Host "   [FAIL] User creation failed" -ForegroundColor Red
            $failed++
            continue
        }

        # Grant SYSADMIN role
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $grantResult = & snow sql -c training -q "GRANT ROLE SYSADMIN TO USER $($l.Name)" 2>&1
        $ErrorActionPreference = $prevEAP

        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [PASS] SYSADMIN role granted" -ForegroundColor Green
        } else {
            Write-Host "   [WARN] Role grant failed" -ForegroundColor Yellow
        }
    }

    $passwordLines += "$($l.Name)|$($l.Password)"
    Write-Host ''
}

# ------------------------------------------------------------------
# Save passwords
# ------------------------------------------------------------------

if (-not $DryRun) {
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    }
    $passwordLines | Set-Content -Path $secretsFile -Encoding utf8
    Write-Host "Passwords saved to: $secretsFile" -ForegroundColor DarkGray
    Write-Host ''
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Created      : $created"
Write-Host "  Already exist: $existing"
Write-Host "  Failed       : $failed"
Write-Host ''

if ($failed -gt 0) {
    Write-Host 'Status: PARTIAL' -ForegroundColor Yellow
    exit 1
} else {
    Write-Host 'Status: DONE' -ForegroundColor Green
    if (-not $DryRun) {
        Write-Host ''
        Write-Host 'Learners can login to Snowflake web:' -ForegroundColor DarkGray
        Write-Host '  https://app.snowflake.com' -ForegroundColor DarkGray
        Write-Host "  Username: apprenant01 to apprenant10" -ForegroundColor DarkGray
        Write-Host "  Password: from $secretsFile" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'Or via CLI:' -ForegroundColor DarkGray
        Write-Host '  snow sql -c training -q "SELECT 1" (uses shared PAT)' -ForegroundColor DarkGray
    }
    exit 0
}
