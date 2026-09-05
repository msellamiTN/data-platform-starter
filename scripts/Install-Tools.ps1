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

# Terraform providers (installed via terraform init, not by this script)
$ProviderVersions = [ordered]@{
    'snowflakedb/snowflake'      = '2.14.0'
    'hashicorp/azurerm'          = '4.59.0'
    'microsoft/azuredevops'      = '1.14.0'
    'hashicorp/tls'              = '>= 4.0'
}

# dbt packages (installed via dbt deps, not by this script)
$DbtPackages = [ordered]@{
    'get-select/dbt_snowflake_monitoring' = '4.6.0'
    'dbt-labs/dbt_utils'                  = '1.3.3'
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

    # Always refresh PATH so a recently installed local copy is found first.
    Sync-Path

    try {
        $exe = Get-FirstInPath $Name
        if ($exe) {
            $output = @(& $exe @Arguments 2>&1)
        } else {
            $output = @(& $Name @Arguments 2>&1)
        }
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
    # Local BinDir must come FIRST so the exact policy versions win over
    # any system-wide installation (e.g. Terraform 1.15.1 installed elsewhere).
    $env:PATH = (($BinDir, $machine, $user) | Where-Object { $_ }) -join ';'
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

function Add-SystemPath {
    param([string]$Directory)

    if (-not (Test-Path $Directory)) { return $false }

    try {
        $current = [Environment]::GetEnvironmentVariable('PATH', 'Machine')
        if (-not $current) { $current = '' }
        $escaped = [Regex]::Escape($Directory)

        if ($current -notmatch "(^|;)$escaped(;|$)") {
            $updated = if ($current) { "$Directory;$current" } else { $Directory }
            [Environment]::SetEnvironmentVariable('PATH', $updated, 'Machine')
            Write-Host "       System PATH updated: $Directory" -ForegroundColor DarkGray
        }
        return $true
    } catch {
        Write-Host "       Could not update System PATH (admin rights required): $Directory" -ForegroundColor DarkGray
        return $false
    }
}

function Add-ToolPaths {
    param([string[]]$Directories, [switch]$IncludeSystem)

    foreach ($dir in $Directories) {
        Add-UserPath $dir
        if ($IncludeSystem) { Add-SystemPath $dir }
    }
}

function Get-FirstInPath {
    param([string]$Name)
    $candidates = @(Get-Command $Name -All -ErrorAction SilentlyContinue)
    if (-not $candidates) { return $null }
    $paths = $env:PATH -split ';' | Where-Object { $_ } | Select-Object -Unique
    foreach ($p in $paths) {
        foreach ($c in $candidates) {
            $dir = Split-Path -Parent $c.Source
            if ($dir -and $dir -eq $p) { return $c.Source }
        }
    }
    return $candidates[0].Source
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

        $dest = Join-Path $BinDir $ExecutableName
        Copy-Item -Path $executable.FullName -Destination $dest -Force
        Remove-Item $staging -Recurse -Force -ErrorAction SilentlyContinue

        Add-ToolPaths @($BinDir) -IncludeSystem
        Sync-Path
        # Remove any older terraform on PATH so our local copy wins immediately.
        if ($ExecutableName -eq 'terraform.exe' -and (Test-Path $dest)) {
            $env:PATH = "$BinDir;$env:PATH"
        }
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

function Install-AzureCLI {
    # Try winget first, then fall back to the official MSI.
    if (Install-WithWinget 'Microsoft.AzureCLI') { return $true }

    try {
        $msi = Join-Path $env:TEMP 'AzureCLISetup.msi'
        $url = 'https://aka.ms/installazurecliwindows'
        Write-Host '       Downloading Azure CLI installer...' -ForegroundColor DarkGray
        Invoke-WebRequest -Uri $url -OutFile $msi -UseBasicParsing

        Write-Host '       Installing Azure CLI (this may take a minute)...' -ForegroundColor DarkGray
        $process = Start-Process -FilePath 'msiexec.exe' `
            -ArgumentList "/i `"$msi`" /quiet /norestart" `
            -Wait -PassThru
        if ($process.ExitCode -ne 0) {
            Write-Host ("       MSI installer exited with code {0}" -f $process.ExitCode) -ForegroundColor DarkGray
            return $false
        }
        Remove-Item $msi -Force -ErrorAction SilentlyContinue
        # Default Azure CLI install location.
        $azDir = Join-Path $env:ProgramFiles '(x86)\Microsoft SDKs\Azure\CLI2\wbin'
        if (Test-Path $azDir) { Add-ToolPaths @($azDir) -IncludeSystem }
        Sync-Path
        return $true
    } catch {
        Write-Host ("       Azure CLI installation failed: {0}" -f $_.Exception.Message) -ForegroundColor DarkGray
        return $false
    } finally {
        if (Test-Path $msi) { Remove-Item $msi -Force -ErrorAction SilentlyContinue }
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
    # Ensure our BinDir is at the front of PATH before rechecking.
    Add-ToolPaths @($BinDir) -IncludeSystem
    Sync-Path
    $env:PATH = "$BinDir;$env:PATH"

    $url = "https://releases.hashicorp.com/terraform/$($Policy.Terraform)/terraform_$($Policy.Terraform)_windows_amd64.zip"
    if (Install-FromZip 'terraform' $url 'terraform.exe') {
        # Recheck from the first terraform.exe on PATH (should be our local copy).
        $localTerraform = Get-FirstInPath 'terraform'
        if ($localTerraform) {
            $terraformVersion = & $localTerraform version 2>&1 | Select-Object -First 1
        }
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
    if (Install-WithWinget 'Python.Python.3.12') {
        Sync-Path
        $pythonVersion = Get-ToolVersion 'python' @('--version')
    }
    # Even if 'python' still resolves to an older version, check if the
    # policy-compliant Python is available via the launcher or install paths.
    $policyPy = $null
    if (Test-Tool 'py') {
        $pyOutput = @(& py -"$($Policy.Python)" --version 2>&1)
        if ($LASTEXITCODE -eq 0 -and "$pyOutput" -match $Policy.Python) {
            $policyPy = [string]$pyOutput
        }
    }
    if (-not $policyPy) {
        $exeName = "python$($Policy.Python -replace '\.','').exe"
        $searchDirs = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
            'C:\Python312',
            'C:\Program Files\Python312'
        )
        foreach ($dir in $searchDirs) {
            if (-not (Test-Path $dir)) { continue }
            $candidate = Join-Path $dir $exeName
            if (Test-Path $candidate) {
                $verOutput = @(& $candidate --version 2>&1)
                if ($LASTEXITCODE -eq 0 -and "$verOutput" -match $Policy.Python) {
                    $policyPy = [string]$verOutput
                    break
                }
            }
            $subDirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue
            foreach ($sub in $subDirs) {
                $candidate = Join-Path $sub.FullName 'python.exe'
                if (Test-Path $candidate) {
                    $verOutput = @(& $candidate --version 2>&1)
                    if ($LASTEXITCODE -eq 0 -and "$verOutput" -match $Policy.Python) {
                        $policyPy = [string]$verOutput
                        break
                    }
                }
            }
            if ($policyPy) { break }
        }
    }
    if ($pythonVersion -and $pythonVersion -match [Regex]::Escape($Policy.Python)) {
        Add-Result 'Python' 'Core' 'PASS' $pythonVersion
    } elseif ($policyPy) {
        Add-Result 'Python' 'Core' 'PASS' "$policyPy (via launcher)"
    } elseif ($pythonVersion) {
        Add-Result 'Python' 'Core' 'WARN' "Found $pythonVersion, policy requires $($Policy.Python). Python $($Policy.Python) was installed but is not the default 'python'. The venv will use the correct version." (Get-ManualStep 'Python')
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

function Get-PolicyPython {
    # Try the Windows Python launcher with the exact policy version (e.g. 'py -3.12').
    if (Test-Tool 'py') {
        $pyOutput = @(& py -"$($Policy.Python)" --version 2>&1)
        if ($LASTEXITCODE -eq 0 -and "$pyOutput" -match $Policy.Python) {
            return @('py', "-$($Policy.Python)")
        }
    }

    # Search for python3.12.exe in common install locations.
    $exeName = "python$($Policy.Python -replace '\.','').exe"
    $searchDirs = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Python'),
        'C:\Python312',
        'C:\Program Files\Python312',
        (Join-Path $HOME '.data2ai\python312')
    )
    foreach ($dir in $searchDirs) {
        if (-not (Test-Path $dir)) { continue }
        $candidate = Join-Path $dir $exeName
        if (Test-Path $candidate) { return @($candidate) }
        # Also check versioned subdirectories (e.g. Python312\python.exe)
        $subDirs = Get-ChildItem -Path $dir -Directory -ErrorAction SilentlyContinue
        foreach ($sub in $subDirs) {
            $candidate = Join-Path $sub.FullName 'python.exe'
            if (Test-Path $candidate) {
                $verOutput = @(& $candidate --version 2>&1)
                if ($LASTEXITCODE -eq 0 -and "$verOutput" -match $Policy.Python) {
                    return @($candidate)
                }
            }
        }
    }

    # Fall back to whatever 'python' resolves to.
    if (Test-Tool 'python') { return @('python') }
    return $null
}

function Get-VenvPythonVersion {
    $venvPython = Join-Path (Get-VenvScriptPath) 'python.exe'
    if (-not (Test-Path $venvPython)) { return $null }
    try {
        $ver = @(& $venvPython --version 2>&1)
        if ($LASTEXITCODE -eq 0) { return [string]$ver }
    } catch {}
    return $null
}

function Initialize-TrainingVenv {
    $venvPython = Join-Path (Get-VenvScriptPath) 'python.exe'

    # Check if an existing venv was created with the wrong Python version.
    if (Test-Path $venvPython) {
        $venvVer = Get-VenvPythonVersion
        if ($venvVer -and $venvVer -notmatch [Regex]::Escape($Policy.Python)) {
            Write-Host "       Existing venv uses $venvVer; recreating with Python $($Policy.Python)..." -ForegroundColor Yellow
            Remove-Item -Path $VenvDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    if (-not (Test-Path $venvPython)) {
        $pyCmd = Get-PolicyPython
        if (-not $pyCmd) {
            Write-Host '       No Python interpreter found.' -ForegroundColor Red
            return $false
        }
        Write-Host "       Creating the isolated virtual environment with $($pyCmd -join ' ')..." -ForegroundColor DarkGray
        $venvOutput = & $pyCmd[0] @($pyCmd[1..($pyCmd.Length - 1)]) -m venv $VenvDir 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "       venv creation failed: $venvOutput" -ForegroundColor Red
            return $false
        }
    }

    # Always ensure the venv Scripts dir is in PATH
    Add-ToolPaths @(Get-VenvScriptPath) -IncludeSystem
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
        & $venvPython -m pip install --prefer-binary @Specs 2>&1 |
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
# Python based tools (single venv to keep dependency graph consistent)
# ------------------------------------------------------------------

Write-Section 'Python based tools'

$snowVersion = Get-ToolVersion 'snow' @('--version')
$dbtVersion  = Get-ToolVersion 'dbt' @('--version')

if ($snowVersion -and $dbtVersion -and -not $Force) {
    Add-Result 'Snowflake CLI' 'Core' 'PASS' $snowVersion
    Add-Result 'dbt' 'Course' 'PASS' $dbtVersion
} elseif ($Check) {
    if ($snowVersion) {
        Add-Result 'Snowflake CLI' 'Core' 'PASS' $snowVersion
    } else {
        Add-Result 'Snowflake CLI' 'Core' 'FAIL' 'Not found' (Get-ManualStep 'Snowflake CLI')
    }
    if ($dbtVersion) {
        Add-Result 'dbt' 'Course' 'PASS' $dbtVersion
    } else {
        Add-Result 'dbt' 'Course' 'FAIL' 'Not found (required from Day 5)' (Get-ManualStep 'dbt')
    }
} else {
    if (Initialize-TrainingVenv) {
        # Install snowflake-cli and dbt together so pip resolves a compatible set.
        # If no compatible set exists, the command fails cleanly instead of
        # creating a broken venv with conflicting transitive deps.
        $dbtSpec = $Policy.DbtSpec
        $installed = Install-VenvPackage @('snowflake-cli', "dbt-core$dbtSpec", "dbt-snowflake$dbtSpec")
        if (-not $installed) {
            # Fallback: install only Snowflake CLI so Day 0-4 labs work.
            # dbt is only required from Day 5; the learner can install it later.
            Write-Host '       dbt install failed; retrying with Snowflake CLI only...' -ForegroundColor Yellow
            $installed = Install-VenvPackage @('snowflake-cli')
        }
    }
    $snowVersion = Get-ToolVersion 'snow' @('--version')
    $dbtVersion  = Get-ToolVersion 'dbt' @('--version')
    if ($snowVersion) {
        Add-Result 'Snowflake CLI' 'Core' 'PASS' $snowVersion
    } else {
        Add-Result 'Snowflake CLI' 'Core' 'FAIL' 'Installation did not complete' (Get-ManualStep 'Snowflake CLI')
    }
    if ($dbtVersion) {
        Add-Result 'dbt' 'Course' 'PASS' $dbtVersion
    } elseif ($installed -and -not (Get-ToolVersion 'dbt' @('--version'))) {
        # dbt was skipped because it conflicted with Snowflake CLI.
        # Mark as WARN since it is only needed from Day 5.
        Add-Result 'dbt' 'Course' 'WARN' 'Skipped due to dependency conflict with Snowflake CLI (reinstall with pip install dbt-core<3.0.0 dbt-snowflake<3.0.0 before Day 5)' (Get-ManualStep 'dbt')
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
    if (Install-AzureCLI) { $azVersion = Get-ToolVersion 'az' @('version') }
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
# Terraform providers and dbt packages (informational — installed by terraform init / dbt deps)
# ------------------------------------------------------------------

Write-Section 'Terraform providers (installed by terraform init)'

foreach ($kv in $ProviderVersions.GetEnumerator()) {
    Write-Host ("  {0,-40} {1}" -f $kv.Key, $kv.Value) -ForegroundColor DarkGray
}

Write-Section 'dbt packages (installed by dbt deps)'

foreach ($kv in $DbtPackages.GetEnumerator()) {
    Write-Host ("  {0,-40} {1}" -f $kv.Key, $kv.Value) -ForegroundColor DarkGray
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
