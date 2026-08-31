#requires -version 5.1
<#
.SYNOPSIS
    Creates a Snowflake CLI connection using credentials from .env or a masked prompt.

.DESCRIPTION
    This script reads .env from the project root if it exists. It uses the
    Snowflake parameters found there. If a parameter is missing or .env does
    not exist, the script prompts for it interactively.

    The PAT is read from .env (SNOWFLAKE_PAT) or entered via a masked prompt.
    It is never displayed, never logged, and never passed as a command-line
    argument.

.PARAMETER ConnectionName
    Name of the Snowflake CLI connection to create. Default: value from .env
    or 'training'.

.PARAMETER Organization
    Snowflake organization name. Overrides .env.

.PARAMETER Account
    Snowflake account identifier. Overrides .env.

.PARAMETER User
    Snowflake user name. Overrides .env.

.PARAMETER Role
    Snowflake role to use. Overrides .env.

.PARAMETER Host
    Optional Snowflake host override. Overrides .env.

.EXAMPLE
    .\scripts\New-SnowflakeConnection.ps1
    # Reads everything from .env

.EXAMPLE
    .\scripts\New-SnowflakeConnection.ps1 -ConnectionName training `
        -Organization MYORG -Account MYACCOUNT -User DATA2AI -Role SYSADMIN
    # Overrides .env with explicit values
#>

[CmdletBinding()]
param(
    [string]$ConnectionName,
    [string]$Organization,
    [string]$Account,
    [string]$User,
    [string]$Role,
    [string]$Host
)

$ErrorActionPreference = 'Stop'

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
    Write-Host "[INFO] No .env file found. You will be prompted for all values." -ForegroundColor DarkGray
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

function Read-Required {
    param([string]$Prompt, [string]$Default = '')

    while ($true) {
        Write-Host "$Prompt" -NoNewline -ForegroundColor Yellow
        if ($Default) { Write-Host " [$Default]" -NoNewline }
        Write-Host ": " -NoNewline
        $value = Read-Host
        if ($value) { return $value }
        if ($Default) { return $Default }
        Write-Host "  A value is required." -ForegroundColor Red
    }
}

# ------------------------------------------------------------------
# Resolve parameters
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Snowflake CLI connection setup' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host 'The PAT is read from .env or entered securely.' -ForegroundColor DarkGray
Write-Host 'It is never displayed or logged.' -ForegroundColor DarkGray
Write-Host ''

$ConnectionName = Get-ConfigValue 'SNOWFLAKE_CONNECTION' $ConnectionName 'training'
$Organization   = Get-ConfigValue 'SNOWFLAKE_ORGANIZATION' $Organization
$Account        = Get-ConfigValue 'SNOWFLAKE_ACCOUNT' $Account
$User           = Get-ConfigValue 'SNOWFLAKE_USER' $User
$Role           = Get-ConfigValue 'SNOWFLAKE_ROLE' $Role 'SYSADMIN'
$Host           = Get-ConfigValue 'SNOWFLAKE_HOST' $Host

if (-not $Organization) { $Organization = Read-Required 'Snowflake organization name' }
if (-not $Account)      { $Account      = Read-Required 'Snowflake account name' }
if (-not $User)         { $User         = Read-Required 'Snowflake user name' }

# PAT: try .env first, then prompt
$token = $envValues['SNOWFLAKE_PAT']

if (-not $token) {
    $token = Read-Masked 'Snowflake PAT (token):'
}

if (-not $token) {
    Write-Host '[ERROR] No token available. Aborting.' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Build the snow connection add command
# ------------------------------------------------------------------

$snowArgs = @(
    'connection', 'add',
    '-n', $ConnectionName,
    '-a', $Account,
    '-o', $Organization,
    '-u', $User,
    '-r', $Role,
    '--no-interactive'
)

if ($Host) {
    $snowArgs += @('-h', $Host)
}

# Export the token only for the snow subprocess.
$env:SNOWFLAKE_PAT = $token

Write-Host ''
Write-Host 'Creating the connection...' -ForegroundColor Cyan

try {
    & snow @snowArgs 2>&1 | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }

    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] snow connection add failed with exit code $LASTEXITCODE" -ForegroundColor Red
        exit 1
    }

    Write-Host "[OK] Connection '$ConnectionName' created." -ForegroundColor Green
} catch {
    Write-Host "[ERROR] Failed to create connection: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
} finally {
    Remove-Item Env:SNOWFLAKE_PAT -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------
# Test the connection
# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Testing the connection...' -ForegroundColor Cyan

$env:SNOWFLAKE_PAT = $token

try {
    $testResult = & snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' `
        -c $ConnectionName --format=json 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host '[OK] Connection test succeeded.' -ForegroundColor Green
        Write-Host "       Output: $testResult" -ForegroundColor DarkGray
    } else {
        Write-Host '[WARN] Connection created but test query failed.' -ForegroundColor Yellow
        Write-Host "       Check with: snow connection test -c $ConnectionName" -ForegroundColor DarkGray
    }
} catch {
    Write-Host '[WARN] Connection test could not execute.' -ForegroundColor Yellow
} finally {
    Remove-Item Env:SNOWFLAKE_PAT -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  - Use the connection:  snow sql -q 'SELECT 1' -c $ConnectionName"
Write-Host '  - Do not store the PAT in any committed file.'
Write-Host '  - Rotate the PAT when the training module is complete.'
