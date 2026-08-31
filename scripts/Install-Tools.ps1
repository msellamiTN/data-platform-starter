#requires -version 5.1
<#
.SYNOPSIS
    Installs and verifies the Terraform and Snowflake training toolchain on Windows.

.DESCRIPTION
    Versions come from docs/version-policy.md. The script is idempotent: a tool
    that already matches the policy is left untouched.

    Python based tools are installed in an isolated virtual environment instead
    of the global interpreter. Terraform and tflint are installed under the user
    profile so administrator rights are not required.

    When an installation is blocked, the script prints the official manual
    procedure and continues instead of failing hard.

    Exit code 0 means every required tool is available.

.PARAMETER Check
    Diagnose only. Nothing is downloaded, installed or added to PATH.

.PARAMETER Force
    Reinstall a tool even when it already matches the expected version.

.PARAMETER ReportPath
    Base path for the report. Two files are written: .md and .json.
    No credential is ever written to a report.

.PARAMETER InstallRoot
    Root folder for user scoped installations. Default: $HOME\.data2ai

.PARAMETER SkipOptional
    Ignore optional tools such as VS Code, tflint and OpenSSL.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Tools.ps1 -Check

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Tools.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\Install-Tools.ps1 -ReportPath .\preflight
#>

[CmdletBinding()]
param(
    [switch]$Check,
    [switch]$Force,
    [string]$ReportPath,
    [string]$InstallRoot = (Join-Path $HOME '.data2ai'),
    [switch]$SkipOptional
)

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Versions - keep aligned with docs/version-policy.md
# ------------------------------------------------------------------

$Policy = [ordered]@{
    Terraform    = '1.14.5'
    Python       = '3.12'
    AzureCli     = '2.83.0'
    Tflint       = '0.50.0'
    DbtSpec      = '<3.0.0'
}

$BinDir  = Join-Path $InstallRoot 'bin'
$VenvDir = Join-Path $InstallRoot 'venv'

$Results = [System.Collections.Generic.List[object]]::new()

# ------------------------------------------------------------------
# Output helpers - keep messages ASCII for consistent console rendering
# ------------------------------------------------------------------

function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host "== $Title" -ForegroundColor Cyan
}

function Format-Detail {
    param([string]$Text)
    if (-not $Text) { return '' }
    # Remove pipes so the Markdown table stays valid, collapse whitespace, truncate.
    $clean = ($Text -replace '\|', '/') -replace '\s+', ' '
    $clean = $clean.Trim()
    if ($clean.Length -gt 90) { $clean = $clean.Substring(0, 90) }
    return $clean
}

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet('Core', 'Course', 'Optional')][string]$Tier,
        [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')][string]$Status,
        [string]$Detail,
        [string]$Action = ''
    )

    $Detail = Format-Detail $Detail

    $Results.Add([PSCustomObject]@{
        Name   = $Name
        Tier   = $Tier
        Status = $Status
        Detail = $Detail
        Action = $Action
    })

    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'DarkGray' }
    }

    Write-Host ("[{0}] {1} - {2}" -f $Status, $Name, $Detail) -ForegroundColor $color
    if ($Action) { Write-Host ("       {0}" -f $Action) -ForegroundColor DarkGray }
}

function Test-Tool {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Get-ToolVersion {
    param([string]$Name, [string[]]$Arguments)

    if (-not (Test-Tool $Name)) { return $null }

    try {
        $output = @(& $Name @Arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { return $null }

        $line = $output | Where-Object { "$_".Trim() } | Select-Object -First 1
        if (-not $line) { return $null }

        # Reject output that only reports an execution failure.
        if ("$line" -match 'not recognized|cannot execute|Exec format error') { return $null }

        return [string]$line
    } catch {
        return $null
    }
}

function Sync-Path {
    $machine = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
    $user    = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $env:PATH = @($machine, $user, $BinDir) -ne '' -join ';'
}

function Add-UserPath {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) { return }

    $current = [Environment]::GetEnvironmentVariable('PATH', 'User')
    if (-not $current) { $current = '' }
    $escaped = [Regex]::Escape($Directory)

    if ($current -notmatch "(^|;)$escaped(;|$)") {
        $updated = if ($current) { "$Directory;$current" } else { $Directory }
        [Environment]::SetEnvironmentVariable('PATH', $updated, 'User')
        Write-Host "       User PATH updated: $Directory" -ForegroundColor DarkGray
    }

    if ($env:PATH -notmatch "(^|;)$escaped(;|$)") {
        $env:PATH = "$Directory;$env:PATH"
    }
}

function Install-FromZip {
    param(
        [string]$Name,
        [string]$Url,
        [string]$ExecutableName
    )

    $archive = Join-Path $env:TEMP ("{0}-{1}.zip" -f $Name, [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $BinDir -Force | Out-Null
        Invoke-WebRequest -Uri $Url -OutFile $archive -UseBasicParsing

        $staging = Join-Path $env:TEMP ("{0}-{1}" -f $Name, [Guid]::NewGuid().ToString('N'))
        Expand-Archive -Path $archive -DestinationPath $staging -Force

        $executable = Get-ChildItem -Path $staging -Filter $ExecutableName -Recurse -File |
            Select-Object -First 1

        if (-not $executable) { throw "$ExecutableName not found in the archive." }

        Copy-Item -Path $executable.FullName -Destination (Join-Path $BinDir $ExecutableName) -Force
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

        Add-UserPath $BinDir
        Sync-Path
        return $true
    } catch {
        Write-Host ("       Download or extraction failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray
        return $false
    } finally {
        Remove-Item $archive -Force -ErrorAction SilentlyContinue
    }
}

function Install-WithWinget {
    param([string]$PackageId)

    if (-not (Test-Tool 'winget')) { return $false }

    try {
        winget install --id $PackageId --exact `
            --accept-package-agreements --accept-source-agreements --silent 2>&1 |
            Out-Null
        Start-Sleep -Seconds 2
        Sync-Path
        return $true
    } catch {
        return $false
    }
}

# ------------------------------------------------------------------
# Manual fallback instructions
# ------------------------------------------------------------------

$ManualSteps = @{
    'Git'           = 'Install Git for Windows from the official download page, then open a new terminal.'
    'Terraform'     = "Download Terraform $($Policy.Terraform) for windows_amd64 from the official HashiCorp releases site and place terraform.exe in a folder listed in PATH."
    'Python'        = "Install Python $($Policy.Python) from the official python.org installer and enable 'Add python.exe to PATH'."
    'Snowflake CLI' = 'Install Snowflake CLI with the official Snowflake installer, or inside a Python virtual environment.'
    'dbt'           = 'Install dbt-core and dbt-snowflake (both below version 3) inside a Python virtual environment.'
    'Azure CLI'     = 'Install Azure CLI with the official Microsoft installer for Windows.'
    'tflint'        = "Download tflint $($Policy.Tflint) for windows_amd64 from the official releases page."
    'VS Code'       = 'Install Visual Studio Code from the official Microsoft download page, or use another editor.'
    'OpenSSL'       = 'OpenSSL is bundled with Git for Windows. Add the Git mingw64 bin folder to PATH if the command is missing.'
}

function Get-ManualStep {
    param([string]$Name)
    if ($ManualSteps.ContainsKey($Name)) { return $ManualSteps[$Name] }
    return 'Install this tool with the vendor official procedure.'
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

$mode = if ($Check) { 'CHECK (no installation)' } else { 'INSTALL' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Terraform and Snowflake training toolchain' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Mode         : $mode"
Write-Host " Install root : $InstallRoot"
Write-Host " Policy       : docs/version-policy.md"

Sync-Path

# ------------------------------------------------------------------
# Git
# ------------------------------------------------------------------

Write-Section 'Git'

$gitVersion = Get-ToolVersion 'git' @('--version')

if ($gitVersion -and -not $Force) {
    Add-Result 'Git' 'Core' 'PASS' $gitVersion
} elseif ($Check) {
    Add-Result 'Git' 'Core' 'FAIL' 'Not found' (Get-ManualStep 'Git')
} else {
    if (Install-WithWinget 'Git.Git') { $gitVersion = Get-ToolVersion 'git' @('--version') }
    if ($gitVersion) {
        Add-Result 'Git' 'Core' 'PASS' $gitVersion
    } else {
        Add-Result 'Git' 'Core' 'FAIL' 'Installation did not complete' (Get-ManualStep 'Git')
    }
}

# ------------------------------------------------------------------
# Terraform
# ------------------------------------------------------------------

Write-Section "Terraform $($Policy.Terraform)"

$terraformVersion = Get-ToolVersion 'terraform' @('version')
$terraformMatches = $terraformVersion -and $terraformVersion -match [Regex]::Escape($Policy.Terraform)

if ($terraformMatches -and -not $Force) {
    Add-Result 'Terraform' 'Core' 'PASS' $terraformVersion
} elseif ($Check) {
    $detail = if ($terraformVersion) { "Found $terraformVersion, policy requires $($Policy.Terraform)" } else { 'Not found' }
    Add-Result 'Terraform' 'Core' 'FAIL' $detail (Get-ManualStep 'Terraform')
} else {
    $url = "https://releases.hashicorp.com/terraform/$($Policy.Terraform)/terraform_$($Policy.Terraform)_windows_amd64.zip"
    if (Install-FromZip 'terraform' $url 'terraform.exe') {
        $terraformVersion = Get-ToolVersion 'terraform' @('version')
    }
    if ($terraformVersion -and $terraformVersion -match [Regex]::Escape($Policy.Terraform)) {
        Add-Result 'Terraform' 'Core' 'PASS' $terraformVersion
    } else {
        $detail = if ($terraformVersion) { "Found $terraformVersion, policy requires $($Policy.Terraform)" } else { 'Installation did not complete' }
        Add-Result 'Terraform' 'Core' 'FAIL' $detail (Get-ManualStep 'Terraform')
    }
}

# ------------------------------------------------------------------
# Python
# ------------------------------------------------------------------

Write-Section "Python $($Policy.Python)"

$pythonVersion = Get-ToolVersion 'python' @('--version')
$pythonMatches = $pythonVersion -and $pythonVersion -match [Regex]::Escape($Policy.Python)

if ($pythonMatches -and -not $Force) {
    Add-Result 'Python' 'Core' 'PASS' $pythonVersion
} elseif ($Check) {
    $detail = if ($pythonVersion) { "Found $pythonVersion, policy requires $($Policy.Python)" } else { 'Not found' }
    $status = if ($pythonVersion) { 'WARN' } else { 'FAIL' }
    Add-Result 'Python' 'Core' $status $detail (Get-ManualStep 'Python')
} else {
    if (Install-WithWinget 'Python.Python.3.12') { $pythonVersion = Get-ToolVersion 'python' @('--version') }
    if ($pythonVersion -and $pythonVersion -match [Regex]::Escape($Policy.Python)) {
        Add-Result 'Python' 'Core' 'PASS' $pythonVersion
    } elseif ($pythonVersion) {
        Add-Result 'Python' 'Core' 'WARN' "Found $pythonVersion, policy requires $($Policy.Python)" (Get-ManualStep 'Python')
    } else {
        Add-Result 'Python' 'Core' 'FAIL' 'Installation did not complete' (Get-ManualStep 'Python')
    }
}

# ------------------------------------------------------------------
# Isolated virtual environment for Python based tools
# ------------------------------------------------------------------

function Get-VenvScriptPath {
    return (Join-Path $VenvDir 'Scripts')
}

function Initialize-TrainingVenv {
    if (-not (Test-Tool 'python')) { return $false }

    $venvPython = Join-Path (Get-VenvScriptPath) 'python.exe'

    if (-not (Test-Path $venvPython)) {
        Write-Host '       Creating the isolated virtual environment...' -ForegroundColor DarkGray
        $venvOutput = & python -m venv $VenvDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "       venv creation failed: $venvOutput" -ForegroundColor Red
            return $false
        }
    }

    # Always ensure the venv Scripts dir is in PATH
    Add-UserPath (Get-VenvScriptPath)
    Sync-Path

    return (Test-Path $venvPython)
}

function Install-VenvPackage {
    param([string[]]$Specs)

    $venvPython = Join-Path (Get-VenvScriptPath) 'python.exe'
    if (-not (Test-Path $venvPython)) { return $false }

    try {
        Write-Host "       Upgrading pip..." -ForegroundColor DarkGray
        & $venvPython -m pip install --upgrade pip 2>&1 |
            ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }

        Write-Host "       Installing: $($Specs -join ' ')" -ForegroundColor DarkGray
        & $venvPython -m pip install @Specs 2>&1 |
            ForEach-Object { Write-Host "       $_" -ForegroundColor DarkGray }

        if ($LASTEXITCODE -ne 0) {
            Write-Host "       pip install exited with code $LASTEXITCODE" -ForegroundColor Red
            return $false
        }
        return $true
    } catch {
        Write-Host "       pip install exception: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# ------------------------------------------------------------------
# Snowflake CLI
# ------------------------------------------------------------------

Write-Section 'Snowflake CLI'

$snowVersion = Get-ToolVersion 'snow' @('--version')

if ($snowVersion -and -not $Force) {
    Add-Result 'Snowflake CLI' 'Core' 'PASS' $snowVersion
} elseif ($Check) {
    Add-Result 'Snowflake CLI' 'Core' 'FAIL' 'Not found' (Get-ManualStep 'Snowflake CLI')
} else {
    $installed = $false
    if (Initialize-TrainingVenv) {
        $installed = Install-VenvPackage @('snowflake-cli')
    }
    $snowVersion = Get-ToolVersion 'snow' @('--version')
    if ($snowVersion) {
        Add-Result 'Snowflake CLI' 'Core' 'PASS' $snowVersion
    } else {
        Add-Result 'Snowflake CLI' 'Core' 'FAIL' 'Installation did not complete' (Get-ManualStep 'Snowflake CLI')
    }
}

# ------------------------------------------------------------------
# dbt
# ------------------------------------------------------------------

Write-Section "dbt $($Policy.DbtSpec)"

$dbtVersion = Get-ToolVersion 'dbt' @('--version')

if ($dbtVersion -and -not $Force) {
    Add-Result 'dbt' 'Course' 'PASS' $dbtVersion
} elseif ($Check) {
    Add-Result 'dbt' 'Course' 'FAIL' 'Not found (required from Day 5)' (Get-ManualStep 'dbt')
} else {
    $installed = $false
    if (Initialize-TrainingVenv) {
        # Use pip constraint syntax that avoids shell escaping issues with '<'
        $dbtSpec = $Policy.DbtSpec
        $installed = Install-VenvPackage @("dbt-core$dbtSpec", "dbt-snowflake$dbtSpec")
    }
    $dbtVersion = Get-ToolVersion 'dbt' @('--version')
    if ($dbtVersion) {
        Add-Result 'dbt' 'Course' 'PASS' $dbtVersion
    } else {
        Add-Result 'dbt' 'Course' 'FAIL' 'Installation did not complete' (Get-ManualStep 'dbt')
    }
}

# ------------------------------------------------------------------
# Azure CLI
# ------------------------------------------------------------------

Write-Section "Azure CLI $($Policy.AzureCli)"

$azVersion = Get-ToolVersion 'az' @('version')

if ($azVersion -and -not $Force) {
    Add-Result 'Azure CLI' 'Course' 'PASS' 'Available'
} elseif ($Check) {
    Add-Result 'Azure CLI' 'Course' 'FAIL' 'Not found (required from Day 2)' (Get-ManualStep 'Azure CLI')
} else {
    if (Install-WithWinget 'Microsoft.AzureCLI') { $azVersion = Get-ToolVersion 'az' @('version') }
    if ($azVersion) {
        Add-Result 'Azure CLI' 'Course' 'PASS' 'Available'
    } else {
        Add-Result 'Azure CLI' 'Course' 'FAIL' 'Installation did not complete' (Get-ManualStep 'Azure CLI')
    }
}

# ------------------------------------------------------------------
# Optional tools
# ------------------------------------------------------------------

if ($SkipOptional) {
    Write-Section 'Optional tools'
    Add-Result 'Optional tools' 'Optional' 'SKIP' 'Skipped by request'
} else {

    Write-Section "tflint $($Policy.Tflint)"

    $tflintVersion = Get-ToolVersion 'tflint' @('--version')
    if ($tflintVersion -and -not $Force) {
        Add-Result 'tflint' 'Optional' 'PASS' $tflintVersion
    } elseif ($Check) {
        Add-Result 'tflint' 'Optional' 'WARN' 'Not found' (Get-ManualStep 'tflint')
    } else {
        $url = "https://github.com/terraform-linters/tflint/releases/download/v$($Policy.Tflint)/tflint_windows_amd64.zip"
        if (Install-FromZip 'tflint' $url 'tflint.exe') { $tflintVersion = Get-ToolVersion 'tflint' @('--version') }
        if ($tflintVersion) {
            Add-Result 'tflint' 'Optional' 'PASS' $tflintVersion
        } else {
            Add-Result 'tflint' 'Optional' 'WARN' 'Installation did not complete' (Get-ManualStep 'tflint')
        }
    }

    Write-Section 'VS Code'

    $codeVersion = Get-ToolVersion 'code' @('--version')
    if ($codeVersion -and -not $Force) {
        Add-Result 'VS Code' 'Optional' 'PASS' $codeVersion
    } elseif ($Check) {
        Add-Result 'VS Code' 'Optional' 'WARN' 'Not found' (Get-ManualStep 'VS Code')
    } else {
        if (Install-WithWinget 'Microsoft.VisualStudioCode') { $codeVersion = Get-ToolVersion 'code' @('--version') }
        if ($codeVersion) {
            Add-Result 'VS Code' 'Optional' 'PASS' $codeVersion
        } else {
            Add-Result 'VS Code' 'Optional' 'WARN' 'Installation did not complete' (Get-ManualStep 'VS Code')
        }
    }

    Write-Section 'OpenSSL'

    $opensslVersion = Get-ToolVersion 'openssl' @('version')

    if (-not $opensslVersion -and -not $Check) {
        foreach ($candidate in @('C:\Program Files\Git\mingw64\bin', 'C:\Program Files\Git\usr\bin')) {
            if (Test-Path (Join-Path $candidate 'openssl.exe')) {
                Add-UserPath $candidate
                Sync-Path
                $opensslVersion = Get-ToolVersion 'openssl' @('version')
                break
            }
        }
    }

    if ($opensslVersion) {
        Add-Result 'OpenSSL' 'Optional' 'PASS' $opensslVersion
    } else {
        Add-Result 'OpenSSL' 'Optional' 'WARN' 'Not found' (Get-ManualStep 'OpenSSL')
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Sync-Path

$coreFailures   = @($Results | Where-Object { $_.Tier -eq 'Core'   -and $_.Status -eq 'FAIL' })
$courseFailures = @($Results | Where-Object { $_.Tier -eq 'Course' -and $_.Status -eq 'FAIL' })
$warnings       = @($Results | Where-Object { $_.Status -eq 'WARN' })

Write-Section 'Summary'

Write-Host ("Core tools (Day 1)      : {0}" -f $(if ($coreFailures.Count -eq 0) { 'READY' } else { "$($coreFailures.Count) missing" }))
Write-Host ("Course tools (Day 2-5)  : {0}" -f $(if ($courseFailures.Count -eq 0) { 'READY' } else { "$($courseFailures.Count) missing" }))
Write-Host ("Warnings                : {0}" -f $warnings.Count)

if ($coreFailures.Count -gt 0 -or $courseFailures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Action required:' -ForegroundColor Yellow
    foreach ($item in ($coreFailures + $courseFailures)) {
        Write-Host ("  - {0}: {1}" -f $item.Name, $item.Action) -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'If a command is still not found, close and reopen your terminal.' -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Report
# ------------------------------------------------------------------

if ($ReportPath) {
    $markdownPath = "$ReportPath.md"
    $jsonPath     = "$ReportPath.json"

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add('# Toolchain report')
    $lines.Add('')
    $lines.Add("Mode: $mode")
    $lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $lines.Add('')
    $lines.Add('| Tool | Tier | Status | Detail |')
    $lines.Add('|---|---|---|---|')
    foreach ($item in $Results) {
        $lines.Add(("| {0} | {1} | {2} | {3} |" -f $item.Name, $item.Tier, $item.Status, $item.Detail))
    }
    $lines.Add('')
    $lines.Add("Core failures: $($coreFailures.Count)")
    $lines.Add("Course failures: $($courseFailures.Count)")
    $lines.Add("Warnings: $($warnings.Count)")

    $lines | Set-Content -Path $markdownPath -Encoding utf8
    $Results | ConvertTo-Json -Depth 3 | Set-Content -Path $jsonPath -Encoding utf8

    Write-Host ''
    Write-Host "Report: $markdownPath" -ForegroundColor DarkGray
    Write-Host "Report: $jsonPath" -ForegroundColor DarkGray
}

if ($coreFailures.Count -gt 0) {
    Write-Host ''
    Write-Host 'Toolchain status: NOT READY' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Toolchain status: READY' -ForegroundColor Green
exit 0
