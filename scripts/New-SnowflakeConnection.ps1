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

# Force UTF-8 for Python stdout/stderr on Windows (cp1252 locale).
# DO NOT set PYTHONUTF8=1: it makes Python decode subprocess output (e.g. icacls)
# as UTF-8, which crashes on French Windows where icacls emits cp1252 bytes.
# Actively remove it if a previous session left it in the environment.
$env:PYTHONIOENCODING = 'utf-8'
Remove-Item Env:\PYTHONUTF8 -ErrorAction SilentlyContinue

# ------------------------------------------------------------------
# Load .env if it exists (force UTF-8 to avoid cp1252 decoding errors)
# ------------------------------------------------------------------

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$envFile = Join-Path $projectRoot '.env'

$envValues = @{}

if (Test-Path $envFile) {
    Write-Host "[INFO] Loading .env from $envFile" -ForegroundColor DarkGray
    Get-Content $envFile -Encoding UTF8 | ForEach-Object {
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
# Resolve PAT: .env variable > file > $env:TF_VAR_snowflake_token > prompt
# ------------------------------------------------------------------

$token = $envValues['SNOWFLAKE_PAT']
$patFilePath = Join-Path $projectRoot $PatFileRel

if (-not $token) {
    if (Test-Path $patFilePath) {
        Write-Host "[INFO] Reading PAT from $PatFileRel" -ForegroundColor DarkGray
        $token = (Get-Content $patFilePath -Encoding UTF8 -Raw).Trim()
    }
}

# Fallback: use TF_VAR_snowflake_token set by Learner-Login.ps1 in the current session
if (-not $token -and $env:TF_VAR_snowflake_token) {
    Write-Host "[INFO] Reading PAT from `$env:TF_VAR_snowflake_token (set by Learner-Login)" -ForegroundColor DarkGray
    $token = $env:TF_VAR_snowflake_token.Trim()
}

if (-not $token) {
    Write-Host "[INFO] SNOWFLAKE_PAT not found in .env, PAT file, or session env." -ForegroundColor Yellow
    $token = Read-Masked 'Enter Snowflake PAT (token):'
}

if (-not $token) {
    Write-Host '[ERROR] No token available. Aborting.' -ForegroundColor Red
    exit 1
}

# PATs are JWTs and should only contain base64url characters.
if ($token -notmatch '^[A-Za-z0-9_\-\.]+$') {
    Write-Host '[ERROR] PAT contains characters that are not valid in a JWT (spaces, quotes, non-ASCII, etc.).' -ForegroundColor Red
    Write-Host '       Re-paste the PAT from your clipboard or ask the instructor for a fresh PAT.' -ForegroundColor Red
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
    $existing = (Get-Content $patFilePath -Encoding UTF8 -Raw).Trim()
    if ($existing -eq $token) { $needWrite = $false }
}

if ($needWrite) {
    Write-Host "[INFO] Writing PAT to $PatFileRel" -ForegroundColor DarkGray
    # Write UTF-8 without BOM so snow CLI can read it reliably.
    [System.IO.File]::WriteAllText($patFilePath, $token, [System.Text.UTF8Encoding]::new($false))
}

# Restrict PAT file permissions to current user only.
# Snowflake CLI v3.25+ (connector 4.4+) enforces strict file permissions.
try {
    $currentUser = (whoami).Trim()
    & icacls $patFilePath /inheritance:r 2>&1 | Out-Null
    & icacls $patFilePath /grant:r "${currentUser}:(F)" 2>&1 | Out-Null
} catch {
    Write-Host '[WARN] Could not restrict PAT file permissions.' -ForegroundColor Yellow
}

# Validate the PAT file is valid UTF-8 and contains only printable ASCII.
try {
    $bytes = [System.IO.File]::ReadAllBytes($patFilePath)
    [System.Text.Encoding]::UTF8.GetString($bytes) | Out-Null
    $nonAscii = $bytes | Where-Object { ($_ -lt 32 -or $_ -gt 126) -and $_ -ne 13 -and $_ -ne 10 }
    if ($nonAscii) {
        Write-Host '[WARN] PAT file contains non-ASCII bytes. This may cause Snowflake CLI decoding errors.' -ForegroundColor Yellow
        Write-Host '       Re-paste the PAT from your clipboard or ask the instructor for a fresh PAT.' -ForegroundColor Yellow
    }
} catch {
    Write-Host '[ERROR] PAT file is not valid UTF-8.' -ForegroundColor Red
    Write-Host '       Delete secrets/snowflake_pat.txt and re-run this script.' -ForegroundColor Red
    exit 1
}

# ------------------------------------------------------------------
# Write Snowflake CLI config.toml directly
# Avoids `snow connection add` encoding bugs on Windows cp1252 locales.
# ------------------------------------------------------------------

Write-Host 'Creating the connection...' -ForegroundColor Cyan

$snowflakeConfigDir = Join-Path $HOME '.snowflake'
$snowflakeConfigFile = Join-Path $snowflakeConfigDir 'config.toml'

New-Item -ItemType Directory -Path $snowflakeConfigDir -Force | Out-Null

# If a previous config dir exists, remove it entirely to avoid stale/corrupted files.
if (Test-Path $snowflakeConfigFile) {
    try {
        $cfgBytes = [System.IO.File]::ReadAllBytes($snowflakeConfigFile)
        [System.Text.Encoding]::UTF8.GetString($cfgBytes) | Out-Null
    } catch {
        Write-Host '[WARN] Existing Snowflake config.toml is not valid UTF-8; removing it.' -ForegroundColor Yellow
        Remove-Item $snowflakeConfigFile -Force
    }
}

# Snowflake CLI config.toml format:
#   account = "<account_name>"  (e.g. PM71247)
#   host = "<org>-<account>.snowflakecomputing.com"  (explicit to avoid mismatches)
# All values are forced to printable ASCII to avoid any non-UTF-8 bytes.
$accountValue = $Account
$hostValue = if ($SnowflakeHost) { $SnowflakeHost } else { "$Organization-$Account.snowflakecomputing.com" }

# Use forward slashes in the token file path to avoid TOML backslash escaping issues.
$patFilePathTOML = $patFilePath -replace '\\', '/'

$configLines = @(
    "[connections.$ConnectionName]",
    "account = `"$accountValue`"",
    "user = `"$User`"",
    "role = `"$Role`"",
    "authenticator = `"PROGRAMMATIC_ACCESS_TOKEN`"",
    "token_file_path = `"$patFilePathTOML`"",
    "host = `"$hostValue`""
)

[System.IO.File]::WriteAllLines($snowflakeConfigFile, $configLines, [System.Text.UTF8Encoding]::new($false))

# Verify the file we wrote is valid UTF-8 and only printable ASCII.
try {
    $writtenBytes = [System.IO.File]::ReadAllBytes($snowflakeConfigFile)
    [System.Text.Encoding]::UTF8.GetString($writtenBytes) | Out-Null
    $badBytes = $writtenBytes | Where-Object { ($_ -lt 32 -or $_ -gt 126) -and $_ -ne 13 -and $_ -ne 10 }
    if ($badBytes) {
        Write-Host '[ERROR] config.toml contains non-ASCII bytes after writing.' -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host '[ERROR] config.toml is not valid UTF-8 after writing.' -ForegroundColor Red
    exit 1
}

Write-Host "[OK] Connection '$ConnectionName' written to $snowflakeConfigFile" -ForegroundColor Green

# ------------------------------------------------------------------
# Restrict config.toml permissions so Snow CLI doesn't warn about
# unauthorized users (Administrateurs/Système) having access.
# Grant full control to the current user only, remove inherited ACEs
# and the local Administrators group.
# ------------------------------------------------------------------
try {
    # Use whoami to get "DOMAIN\user" — more reliable than $env:USERNAME
    # which can contain spaces (e.g. "Formation Terraform") that break
    # icacls argument parsing when combined with :(F) permissions syntax.
    $currentUser = (whoami).Trim()
    & icacls $snowflakeConfigFile /inheritance:r 2>&1 | Out-Null
    & icacls $snowflakeConfigFile /grant:r "${currentUser}:(F)" 2>&1 | Out-Null
    # Remove the local Administrators group (French: "Administrateurs")
    & icacls $snowflakeConfigFile /remove:g 'Administrateurs' 2>&1 | Out-Null
    & icacls $snowflakeConfigFile /remove:g 'Administrators' 2>&1 | Out-Null
    Write-Host '[OK] Config file permissions restricted to current user.' -ForegroundColor Green
} catch {
    Write-Host '[WARN] Could not restrict config.toml permissions. Snow CLI may show a warning.' -ForegroundColor Yellow
}

# ------------------------------------------------------------------
# Test the connection - token comes from file, no env var needed
# ------------------------------------------------------------------

Write-Host ''
Write-Host 'Testing the connection...' -ForegroundColor Cyan

$prevTestEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

try {
    $testResult = & snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' `
        -c $ConnectionName --format=json 2>&1
    $testExit = $LASTEXITCODE

    # Show full output (not filtered) for debugging without exposing the token value.
    $cleanResult = $testResult | Where-Object { "$_" -notmatch 'Warning|UserWarning|encoding' } | Out-String

    if ($testExit -eq 0 -and $cleanResult) {
        Write-Host '[OK] Connection test succeeded.' -ForegroundColor Green
        Write-Host "       $cleanResult" -ForegroundColor DarkGray
    } else {
        Write-Host '[WARN] Connection created but test query failed.' -ForegroundColor Yellow
        Write-Host '       Output:' -ForegroundColor DarkGray
        Write-Host $cleanResult -ForegroundColor DarkGray
        Write-Host "       Debug with: snow --debug connection test -c $ConnectionName" -ForegroundColor DarkGray
        Write-Host "       Or: snow --debug sql -q 'SELECT 1' -c $ConnectionName" -ForegroundColor DarkGray
    }
} finally {
    $ErrorActionPreference = $prevTestEAP
}

Write-Host ''
Write-Host 'Done.' -ForegroundColor Green
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor Cyan
Write-Host "  - Use the connection:  snow sql -q 'SELECT 1' -c $ConnectionName"
Write-Host '  - The token is read from the file automatically - no env var needed.'
Write-Host '  - Do not store the PAT in any committed file (secrets/ is gitignored).'
Write-Host '  - Rotate the PAT when the training module is complete.'
