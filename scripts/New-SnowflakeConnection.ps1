#requires -version 5.1
<#
.SYNOPSIS
    Creates a Snowflake CLI connection using credentials from .env.

.DESCRIPTION
    Reads .env from the project root. All Snowflake parameters come from .env.
    The PAT is read from SNOWFLAKE_PAT in .env, or from the file pointed to by
    SNOWFLAKE_PAT_FILE. If neither is available, the script prompts for it
    with a masked input.

    The token is written to secrets/snowflake_pat.txt and the connection is
    created with --token-file-path so that 'snow sql -c training' works
    standalone without exporting SNOWFLAKE_PAT each time.

    The PAT is never displayed, never logged, and never passed as a
    command-line argument.

.EXAMPLE
    .\scripts\New-SnowflakeConnection.ps1
    # Reads everything from .env
#>

[CmdletBinding()]
param(
    [string]$ConnectionName,
    [string]$Organization,
    [string]$Account,
    [string]$User,
    [string]$Role,
    [string]$SnowflakeHost
)

$ErrorActionPreference = 'Stop'

# Fix Python encoding mismatch on Windows (cp1252 locale vs utf-8 filesystem)
$env:PYTHONUTF8 = '1'

# ------------------------------------------------------------------
# Load .env if it exists
# ------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$envFile = Join-Path $projectRoot '.env'

$envValues = @{}

if (Test-Path $envFile) {
    Write-Host "[INFO] Loading .env from $envFile" -ForegroundColor DarkGray
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^#') {
            $sep = $line.IndexOf('=')
            if ($sep -gt 0) {
                $key = $line.Substring(0, $sep).Trim()
                $value = $line.Substring($sep + 1).Trim().Trim('"').Trim("'")
                $envValues[$key] = $value
            }
        }
    }
} else {
    Write-Host "[WARN] No .env file found at $envFile" -ForegroundColor Yellow
    Write-Host "       Copy .env.example to .env and fill in your values." -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

function Get-ConfigValue {
    param(
        [string]$Key,
        [string]$Override,
        [string]$Default = ''
    )

    if ($Override) { return $Override }
    if ($envValues.ContainsKey($Key) -and $envValues[$Key]) { return $envValues[$Key] }
    if ($Default) { return $Default }
    return ''
}

function Read-Masked {
    param([string]$Prompt)

    Write-Host "$Prompt " -NoNewline -ForegroundColor Yellow
    $secure = Read-Host -AsSecureString
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

# ------------------------------------------------------------------
# Resolve all parameters from .env
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Snowflake CLI connection setup' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

$ConnectionName = Get-ConfigValue 'SNOWFLAKE_CONNECTION' $ConnectionName 'training'
$Organization   = Get-ConfigValue 'SNOWFLAKE_ORGANIZATION' $Organization
$Account        = Get-ConfigValue 'SNOWFLAKE_ACCOUNT' $Account
$User           = Get-ConfigValue 'SNOWFLAKE_USER' $User
$Role           = Get-ConfigValue 'SNOWFLAKE_ROLE' $Role 'SYSADMIN'
$SnowflakeHost  = Get-ConfigValue 'SNOWFLAKE_HOST' $SnowflakeHost
$PatFileRel     = Get-ConfigValue 'SNOWFLAKE_PAT_FILE' '' 'secrets/snowflake_pat.txt'

# Show resolved values (without secrets)
Write-Host "  Connection : $ConnectionName" -ForegroundColor DarkGray
Write-Host "  Account    : $Organization-$Account" -ForegroundColor DarkGray
Write-Host "  User       : $User" -ForegroundColor DarkGray
Write-Host "  Role       : $Role" -ForegroundColor DarkGray
if ($SnowflakeHost) {
    Write-Host "  Host       : $SnowflakeHost" -ForegroundColor DarkGray
}
Write-Host "  Token file : $PatFileRel" -ForegroundColor DarkGray
Write-Host ''

# Validate required values
$missing = @()
if (-not $Organization) { $missing += 'SNOWFLAKE_ORGANIZATION' }
if (-not $Account)      { $missing += 'SNOWFLAKE_ACCOUNT' }
if (-not $User)         { $missing += 'SNOWFLAKE_USER' }

if ($missing.Count -gt 0) {
    Write-Host "[ERROR] Missing required values in .env:" -ForegroundColor Red
    foreach ($m in $missing) {
        Write-Host "       - $m" -ForegroundColor Red
    }
    Write-Host "       Edit .env and fill in these values." -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------
# Resolve PAT: .env variable > file > prompt
# ------------------------------------------------------------------

$token = $envValues['SNOWFLAKE_PAT']
$patFilePath = Join-Path $projectRoot $PatFileRel

if (-not $token) {
    if (Test-Path $patFilePath) {
        Write-Host "[INFO] Reading PAT from $PatFileRel" -ForegroundColor DarkGray
        $token = (Get-Content $patFilePath -Raw).Trim()
    }
}

if (-not $token) {
    Write-Host "[INFO] SNOWFLAKE_PAT not found in .env or PAT file." -ForegroundColor Yellow
    $token = Read-Masked 'Enter Snowflake PAT (token):'
}

if (-not $token) {
    Write-Host '[ERROR] No token available. Aborting.' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Write the token to the PAT file so the connection can find it
# ------------------------------------------------------------------

$patDir = Split-Path -Parent $patFilePath
if (-not (Test-Path $patDir)) {
    New-Item -ItemType Directory -Path $patDir -Force | Out-Null
}

# Only write if the file doesn't already have the same content
$needWrite = $true
if (Test-Path $patFilePath) {
    $existing = (Get-Content $patFilePath -Raw).Trim()
    if ($existing -eq $token) { $needWrite = $false }
}

if ($needWrite) {
    Write-Host "[INFO] Writing PAT to $PatFileRel" -ForegroundColor DarkGray
    [System.IO.File]::WriteAllText($patFilePath, $token)
}

# ------------------------------------------------------------------
# Build the snow connection add command
# The --token-file-path stores the path in config.toml so that
# 'snow sql -c training' reads the token from the file automatically.
# ------------------------------------------------------------------

$snowArgs = @(
    'connection', 'add',
    '-n', $ConnectionName,
    '-a', "$Organization-$Account",
    '-u', $User,
    '-r', $Role,
    '-A', 'PROGRAMMATIC_ACCESS_TOKEN',
    '-t', $patFilePath,
    '--no-interactive'
)

if ($SnowflakeHost) {
    $snowArgs += @('-h', $SnowflakeHost)
}

# ------------------------------------------------------------------
# Drop existing connection if it already exists (idempotent)
# ------------------------------------------------------------------

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

$dropOutput = & snow connection remove $ConnectionName 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "[INFO] Removed existing connection '$ConnectionName'." -ForegroundColor DarkGray
}

$ErrorActionPreference = $prevEAP

# ------------------------------------------------------------------
# Create the connection
# ------------------------------------------------------------------

Write-Host 'Creating the connection...' -ForegroundColor Cyan

# Temporarily relax error preference so stderr warnings don't kill the script.
$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

try {
    $snowOutput = & snow @snowArgs 2>&1
    $snowExit = $LASTEXITCODE

    foreach ($line in $snowOutput) {
        $text = "$line"
        if ($text -match 'Warning|UserWarning|encoding') {
            Write-Host "       [warn] $text" -ForegroundColor Yellow
        } elseif ($text -match 'Error|No such option|Usage') {
            Write-Host "       [error] $text" -ForegroundColor Red
        } else {
            Write-Host "       $text" -ForegroundColor DarkGray
        }
    }

    if ($snowExit -ne 0) {
        Write-Host "[ERROR] snow connection add failed with exit code $snowExit" -ForegroundColor Red
        $ErrorActionPreference = $prevEAP
        exit 1
    }

    Write-Host "[OK] Connection '$ConnectionName' created." -ForegroundColor Green
} finally {
    $ErrorActionPreference = $prevEAP
}

# ------------------------------------------------------------------
# Test the connection — no env var needed, token comes from file
# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Testing the connection...' -ForegroundColor Cyan

$ErrorActionPreference = 'Continue'

try {
    $testResult = & snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' `
        -c $ConnectionName --format=json 2>&1
    $testExit = $LASTEXITCODE

    $cleanResult = ($testResult | Where-Object { "$_" -notmatch 'Warning|UserWarning|encoding' })

    if ($testExit -eq 0 -and $cleanResult) {
        Write-Host '[OK] Connection test succeeded.' -ForegroundColor Green
        Write-Host "       $cleanResult" -ForegroundColor DarkGray
    } else {
        Write-Host '[WARN] Connection created but test query failed.' -ForegroundColor Yellow
        Write-Host "       Check with: snow connection test -c $ConnectionName" -ForegroundColor DarkGray
    }
} finally {
    $ErrorActionPreference = $prevEAP
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  - Use the connection:  snow sql -q 'SELECT 1' -c $ConnectionName"
Write-Host '  - The token is read from the file automatically — no env var needed.'
Write-Host '  - Do not store the PAT in any committed file (secrets/ is gitignored).'
Write-Host '  - Rotate the PAT when the training module is complete.'
