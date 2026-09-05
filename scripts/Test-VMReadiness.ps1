#requires -version 5.1
<#
.SYNOPSIS
    VM readiness preflight for preconfigured training VMs.

.DESCRIPTION
    Verifies that a preconfigured VM (tools already installed by the instructor)
    is ready to start the Terraform/Snowflake training labs.

    This script is NON DESTRUCTIVE: it never installs, modifies, or deletes
    anything. It only calls existing scripts in check/diagnostic mode and
    classifies the results.

    Phases:
      1. Tool verification        -> Install-Tools.ps1 -Check
      2. Configuration verification -> .env, LEARNER_PREFIX, gitignore, placeholders
      3. Connectivity verification  -> Test-LabConnectivity.ps1 -SkipDevOps
      4. Consolidated report        -> reports/vm-readiness.md and .json

    Each failure is classified into one of four categories so the learner
    knows whether to fix it themselves or escalate to the instructor:
      - learner-tool       : missing/wrong/broken tool -> run Install-Tools.ps1
      - learner-config     : .env / LEARNER_PREFIX / gitignore problem
      - credential         : Snowflake query or Azure login fails
      - instructor-side    : Blob write / Key Vault RBAC problem

    No PAT, password, or secret is ever written to a report or displayed.

.PARAMETER LearnerPrefix
    Learner prefix (APP01, APP02, ...). If omitted, only Phase 1 (tools)
    and Phase 2 (config) run; Phase 3 (connectivity) is skipped because
    Learner-Login must have been run first.

.PARAMETER ReportPath
    Base path for the report. Two files are written: .md and .json.
    Default: reports/vm-readiness under the project root.

.PARAMETER SkipConnectivity
    Skip Phase 3 (connectivity). Useful before Azure/Snowflake are configured.

.PARAMETER SkipConfig
    Skip Phase 2 (configuration). Useful for a quick tool-only check.

.EXAMPLE
    .\scripts\Test-VMReadiness.ps1
    # Tool-only check (no learner prefix, no connectivity)

.EXAMPLE
    .\scripts\Test-VMReadiness.ps1 -LearnerPrefix APP01
    # Full check: tools + config + connectivity

.EXAMPLE
    .\scripts\Test-VMReadiness.ps1 -LearnerPrefix APP01 -SkipConnectivity
    # Tools + config only (before Learner-Login has been run)

.EXAMPLE
    .\scripts\Test-VMReadiness.ps1 -ReportPath .\reports\vm01
    # Custom report path
#>

[CmdletBinding()]
param(
    [ValidatePattern('^APP\d{2}$')]
    [string]$LearnerPrefix,

    [string]$ReportPath,

    [switch]$SkipConnectivity,
    [switch]$SkipConfig
)

$ErrorActionPreference = 'Continue'

# ------------------------------------------------------------------
# Resolve paths
# ------------------------------------------------------------------

$scriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

if (-not $ReportPath) {
    $ReportPath = Join-Path $projectRoot 'reports\vm-readiness'
}

# ------------------------------------------------------------------
# Ensure local toolchain wins over system-wide installs in this session
# (same logic as Learner-Login.ps1)
# ------------------------------------------------------------------

$localBin     = Join-Path $HOME '.data2ai\bin'
$localVenv    = Join-Path $HOME '.data2ai\venv\Scripts'
$localDbtVenv = Join-Path $HOME '.data2ai\venv-dbt\Scripts'
foreach ($dir in @($localBin, $localVenv, $localDbtVenv)) {
    if (Test-Path $dir) {
        $escaped = [Regex]::Escape($dir)
        if ($env:PATH -notmatch "(^|;)$escaped(;|$)") {
            $env:PATH = "$dir;$env:PATH"
        }
    }
}

# ------------------------------------------------------------------
# Results collection
# ------------------------------------------------------------------

$Results = [System.Collections.Generic.List[object]]::new()
$script:currentPhase = ''

function Set-Phase {
    param([string]$Name)
    $script:currentPhase = $Name
}

function Add-Result {
    param(
        [string]$Name,
        [ValidateSet('PASS','FAIL','WARN','SKIP')][string]$Status,
        [string]$Detail,
        [ValidateSet('learner-tool','learner-config','credential','instructor-side','none')][string]$Category = 'none',
        [string]$RecommendedAction = ''
    )

    $Results.Add([PSCustomObject]@{
        Phase             = $script:currentPhase
        Name              = $Name
        Status            = $Status
        Detail            = $Detail
        Category          = $Category
        RecommendedAction = $RecommendedAction
    })

    $color = switch ($Status) {
        'PASS' { 'Green' }
        'FAIL' { 'Red' }
        'WARN' { 'Yellow' }
        default { 'DarkGray' }
    }
    Write-Host ("  [{0}] {1}" -f $Status, $Name) -ForegroundColor $color
    if ($Detail) {
        Write-Host "         $Detail" -ForegroundColor DarkGray
    }
    if ($Status -eq 'FAIL' -and $RecommendedAction) {
        Write-Host "         -> $RecommendedAction" -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

$vmName = $env:COMPUTERNAME
$vmUser = $env:USERNAME

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' VM Readiness Preflight' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host "  VM host      : $vmName"
Write-Host "  User         : $vmUser"
if ($LearnerPrefix) {
    Write-Host "  Learner      : $LearnerPrefix"
} else {
    Write-Host "  Learner      : (not specified - tool check only)"
}
if ($SkipConnectivity) {
    Write-Host "  Connectivity : SKIPPED by -SkipConnectivity"
}
Write-Host ''

# Track whether Learner-Login has been run in this session.
$learnerLoginDone = $false

# ------------------------------------------------------------------
# Phase 1 — Tool verification (calls Install-Tools.ps1 -Check)
# ------------------------------------------------------------------

Set-Phase '1. Tools'
Write-Host '== Phase 1: Tool verification' -ForegroundColor Cyan

$installScript = Join-Path $scriptDir 'Install-Tools.ps1'
if (-not (Test-Path $installScript)) {
    Add-Result 'Install-Tools.ps1' 'FAIL' "Script not found at $installScript" 'learner-tool' 'Clone the starter project: git clone https://github.com/msellamiTN/data-platform-starter.git'
} else {
    # Use a temporary report path so we can parse the JSON output.
    $tempReportBase = Join-Path $env:TEMP "vm-readiness-tools-$([Guid]::NewGuid().ToString('N'))"
    $tempReportJson = "$tempReportBase.json"

    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & powershell -ExecutionPolicy Bypass -NoProfile -File $installScript -Check -ReportPath $tempReportBase 2>&1 |
            ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        $installExit = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # Parse the JSON report if it exists.
    $toolResults = @()
    if (Test-Path $tempReportJson) {
        try {
            $toolResults = Get-Content $tempReportJson -Raw | ConvertFrom-Json
        } catch {
            $toolResults = @()
        }
    }

    # Classify each tool result.
    $coreFail = 0
    $courseFail = 0
    foreach ($tool in $toolResults) {
        $category = 'none'
        $action   = ''
        if ($tool.Status -eq 'FAIL') {
            $category = 'learner-tool'
            $action   = ".\scripts\Install-Tools.ps1   (then re-run Test-VMReadiness.ps1)"
            if ($tool.Tier -eq 'Core') { $coreFail++ } else { $courseFail++ }
        }
        Add-Result $tool.Name $tool.Status $tool.Detail $category $action
    }

    if ($toolResults.Count -eq 0) {
        Add-Result 'Tool report' 'FAIL' 'Install-Tools.ps1 -Check did not produce a report' 'learner-tool' 'Run: .\scripts\Install-Tools.ps1 -Check'
    }

    # Clean up temp report.
    Remove-Item $tempReportJson -Force -ErrorAction SilentlyContinue
    Remove-Item "$tempReportBase.md" -Force -ErrorAction SilentlyContinue

    if ($coreFail -gt 0) {
        Write-Host ''
        Write-Host "  Core tool failures: $coreFail" -ForegroundColor Red
        Write-Host "  -> Run .\scripts\Install-Tools.ps1 to install/repair missing tools" -ForegroundColor Cyan
    }
}

# ------------------------------------------------------------------
# Phase 2 — Configuration verification
# ------------------------------------------------------------------

Set-Phase '2. Configuration'

if ($SkipConfig) {
    Add-Result 'Configuration' 'SKIP' 'Skipped by -SkipConfig' 'none' ''
} else {
    Write-Host '== Phase 2: Configuration verification' -ForegroundColor Cyan

    # 2a. .env exists
    $envFile = Join-Path $projectRoot '.env'
    if (Test-Path $envFile) {
        Add-Result '.env file' 'PASS' 'Present' 'none' ''
    } else {
        Add-Result '.env file' 'FAIL' "Not found at $envFile" 'learner-config' 'Copy .env.example to .env and set LEARNER_PREFIX'
    }

    # 2b. .env is gitignored
    if (Test-Path $envFile) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $ignored = & git -C $projectRoot check-ignore .env 2>&1
            if ($LASTEXITCODE -eq 0 -and "$ignored" -eq '.env') {
                Add-Result '.env gitignored' 'PASS' 'Protected' 'none' ''
            } else {
                Add-Result '.env gitignored' 'FAIL' '.env is NOT ignored by Git' 'learner-config' 'Add .env to .gitignore before continuing'
            }
        } catch {
            Add-Result '.env gitignored' 'WARN' 'Could not verify (git not available?)' 'none' ''
        } finally {
            $ErrorActionPreference = $prevEAP
        }
    } else {
        Add-Result '.env gitignored' 'SKIP' 'No .env file to check' 'none' ''
    }

    # 2c. secrets/ is gitignored
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $secretsIgnored = & git -C $projectRoot check-ignore secrets/snowflake_pat.txt 2>&1
        if ($LASTEXITCODE -eq 0 -and "$secretsIgnored" -eq 'secrets/snowflake_pat.txt') {
            Add-Result 'secrets/ gitignored' 'PASS' 'Protected' 'none' ''
        } else {
            Add-Result 'secrets/ gitignored' 'FAIL' 'secrets/ is NOT ignored by Git' 'learner-config' 'Add secrets/ to .gitignore'
        }
    } catch {
        Add-Result 'secrets/ gitignored' 'WARN' 'Could not verify' 'none' ''
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # 2d. LEARNER_PREFIX in .env
    $envPrefix = $null
    if (Test-Path $envFile) {
        $envContent = Get-Content $envFile -Encoding UTF8
        foreach ($line in $envContent) {
            $trimmed = $line.Trim()
            if ($trimmed -and $trimmed -notmatch '^#' -and $trimmed -match '^LEARNER_PREFIX\s*=\s*(.+)$') {
                $envPrefix = $matches[1].Trim('"').Trim("'").Trim()
                break
            }
        }
    }

    if ($envPrefix) {
        if ($envPrefix -match '^APP\d{2}$') {
            Add-Result 'LEARNER_PREFIX in .env' 'PASS' $envPrefix 'none' ''
        } else {
            Add-Result 'LEARNER_PREFIX in .env' 'FAIL' "Found '$envPrefix' (must match APP\d{2})" 'learner-config' "Edit .env: LEARNER_PREFIX=APPxx (your assigned prefix)"
        }
    } else {
        Add-Result 'LEARNER_PREFIX in .env' 'FAIL' 'LEARNER_PREFIX not set in .env' 'learner-config' 'Edit .env: LEARNER_PREFIX=APPxx (your assigned prefix)'
    }

    # 2e. No unresolved placeholders in .env
    if (Test-Path $envFile) {
        $envText = Get-Content $envFile -Raw
        # Check for <placeholder> patterns but ignore commented lines (starting with #)
        $uncommentedLines = ($envText -split "`r?`n" | Where-Object { $_ -notmatch '^\s*#' })
        $uncommentedText = $uncommentedLines -join "`n"
        if ($uncommentedText -match '<[^>]+>') {
            Add-Result 'No placeholders in .env' 'FAIL' 'Unresolved <placeholder> values found' 'learner-config' 'Replace every <placeholder> in .env with a real value'
        } else {
            Add-Result 'No placeholders in .env' 'PASS' 'All placeholders resolved' 'none' ''
        }
    }

    # 2f. shared-sp.txt exists (needed for Learner-Login fallback)
    # In KV-first mode, Learner-Login.ps1 auto-creates this file from Key Vault secrets.
    $spFile = Join-Path $projectRoot 'secrets\shared-sp.txt'
    if (Test-Path $spFile) {
        Add-Result 'shared-sp.txt' 'PASS' 'Present' 'none' ''
    } else {
        Add-Result 'shared-sp.txt' 'WARN' 'Not found - will be auto-created by Learner-Login.ps1 (KV-first) or ask instructor' 'credential' 'Run Learner-Login.ps1 (KV-first creates it automatically), or ask instructor for shared-sp.txt'
    }

    # 2g. PAT file exists (needed for Snowflake CLI + Terraform)
    # In KV-first mode, Learner-Login.ps1 auto-creates this file from Key Vault secrets.
    $patFile = Join-Path $projectRoot 'secrets\snowflake_pat.txt'
    if (Test-Path $patFile) {
        $patLen = (Get-Content $patFile -Raw).Trim().Length
        if ($patLen -gt 50) {
            Add-Result 'snowflake_pat.txt' 'PASS' "Present ($patLen chars)" 'none' ''
        } else {
            Add-Result 'snowflake_pat.txt' 'WARN' "File exists but too short ($patLen chars)" 'credential' 'Ask instructor for a valid shared PAT file'
        }
    } else {
        Add-Result 'snowflake_pat.txt' 'WARN' 'Not found - will be auto-created by Learner-Login.ps1 (KV-first) or run New-SnowflakeConnection.ps1' 'credential' 'Run Learner-Login.ps1 (KV-first creates it automatically), or run New-SnowflakeConnection.ps1'
    }

    # 2h. Snowflake CLI config.toml exists with 'training' connection
    $snowConfigFile = Join-Path $HOME '.snowflake\config.toml'
    if (Test-Path $snowConfigFile) {
        $configContent = Get-Content $snowConfigFile -Raw
        if ($configContent -match 'connections\.training\b') {
            Add-Result 'Snow CLI training connection' 'PASS' 'Found in config.toml' 'none' ''
        } else {
            Add-Result 'Snow CLI training connection' 'FAIL' 'training connection not in config.toml' 'credential' 'Run: .\scripts\New-SnowflakeConnection.ps1'
        }
    } else {
        Add-Result 'Snow CLI training connection' 'FAIL' "No config.toml at $snowConfigFile" 'credential' 'Run: .\scripts\New-SnowflakeConnection.ps1'
    }
}

# ------------------------------------------------------------------
# Phase 3 — Connectivity verification (calls Test-LabConnectivity.ps1)
# ------------------------------------------------------------------

Set-Phase '3. Connectivity'

$canRunConnectivity = -not $SkipConnectivity -and $LearnerPrefix

if (-not $canRunConnectivity) {
    if ($SkipConnectivity) {
        Add-Result 'Connectivity' 'SKIP' 'Skipped by -SkipConnectivity' 'none' ''
    } elseif (-not $LearnerPrefix) {
        Add-Result 'Connectivity' 'SKIP' 'Skipped (no -LearnerPrefix provided; run Learner-Login first)' 'none' 'Run: .\scripts\Learner-Login.ps1 -LearnerPrefix APPxx, then re-run Test-VMReadiness.ps1 -LearnerPrefix APPxx'
    }
} else {
    Write-Host '== Phase 3: Connectivity verification' -ForegroundColor Cyan

    # Check if Learner-Login has been run in this session by looking for
    # ARM_SUBSCRIPTION_ID in the environment. If not, advise the learner
    # to run it first.
    $armSubId = $env:ARM_SUBSCRIPTION_ID
    if (-not $armSubId) {
        Add-Result 'Learner-Login session' 'FAIL' 'ARM_SUBSCRIPTION_ID not set - Learner-Login not run in this terminal' 'credential' "Run: .\scripts\Learner-Login.ps1 -LearnerPrefix $LearnerPrefix"
        Write-Host ''
        Write-Host "  -> Learner-Login must be run in this terminal before connectivity can be tested." -ForegroundColor Cyan
        Write-Host "  -> Run: .\scripts\Learner-Login.ps1 -LearnerPrefix $LearnerPrefix" -ForegroundColor Cyan
        Write-Host "  -> Then re-run: .\scripts\Test-VMReadiness.ps1 -LearnerPrefix $LearnerPrefix" -ForegroundColor Cyan
    } else {
        # Learner-Login has been run; call Test-LabConnectivity.ps1 -SkipDevOps
        $connectivityScript = Join-Path $scriptDir 'Test-LabConnectivity.ps1'
        if (-not (Test-Path $connectivityScript)) {
            Add-Result 'Test-LabConnectivity.ps1' 'FAIL' "Script not found at $connectivityScript" 'learner-tool' 'Clone the starter project again'
        } else {
            $tempConnReport = Join-Path $env:TEMP "vm-readiness-conn-$([Guid]::NewGuid().ToString('N'))"
            $tempConnJson   = "$tempConnReport.json"

            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            try {
                & powershell -ExecutionPolicy Bypass -NoProfile -File $connectivityScript -SkipDevOps -ReportPath $tempConnReport 2>&1 |
                    ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
                $connExit = $LASTEXITCODE
            } finally {
                $ErrorActionPreference = $prevEAP
            }

            # Parse the connectivity JSON report.
            $connResults = @()
            if (Test-Path $tempConnJson) {
                try {
                    $connReport = Get-Content $tempConnJson -Raw | ConvertFrom-Json
                    $connResults = $connReport.results
                } catch {
                    $connResults = @()
                }
            }

            # Classify each connectivity result.
            foreach ($item in $connResults) {
                $category = 'none'
                $action   = ''

                if ($item.Status -eq 'FAIL') {
                    $name = $item.Name
                    $detail = $item.Detail

                    # Classify based on the check name.
                    if ($name -match 'Snowflake|snow') {
                        $category = 'credential'
                        $action   = 'Run: .\scripts\New-SnowflakeConnection.ps1'
                    } elseif ($name -match 'Azure CLI auth|Azure auth|Subscription|Service principal') {
                        $category = 'credential'
                        $action   = "Run: .\scripts\Learner-Login.ps1 -LearnerPrefix $LearnerPrefix"
                    } elseif ($name -match 'Blob write|Storage Account|Blob Container') {
                        $category = 'instructor-side'
                        $action   = 'Escalate to instructor: Storage Blob Data Contributor RBAC may be missing or not propagated (up to 10 min)'
                    } elseif ($name -match 'Key Vault') {
                        $category = 'instructor-side'
                        $action   = 'Escalate to instructor: Key Vault Secrets User RBAC may be missing, or vault name is wrong'
                    } elseif ($name -match 'gitignored|Git') {
                        $category = 'learner-config'
                        $action   = 'Fix .gitignore to exclude .env and secrets/'
                    } else {
                        $category = 'credential'
                        $action   = 'Check the connectivity report for details'
                    }
                }

                Add-Result $item.Name $item.Status $detail $category $action
            }

            if ($connResults.Count -eq 0) {
                Add-Result 'Connectivity report' 'FAIL' 'Test-LabConnectivity.ps1 did not produce a report' 'credential' 'Run: .\scripts\Test-LabConnectivity.ps1 -SkipDevOps'
            }

            # Clean up temp report.
            Remove-Item $tempConnJson -Force -ErrorAction SilentlyContinue
            Remove-Item "$tempConnReport.md" -Force -ErrorAction SilentlyContinue
        }
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''

$passCount = @($Results | Where-Object { $_.Status -eq 'PASS' }).Count
$failCount = @($Results | Where-Object { $_.Status -eq 'FAIL' }).Count
$warnCount = @($Results | Where-Object { $_.Status -eq 'WARN' }).Count
$skipCount = @($Results | Where-Object { $_.Status -eq 'SKIP' }).Count

Write-Host "  PASS : $passCount" -ForegroundColor Green
Write-Host "  FAIL : $failCount" -ForegroundColor Red
Write-Host "  WARN : $warnCount" -ForegroundColor Yellow
Write-Host "  SKIP : $skipCount" -ForegroundColor DarkGray
Write-Host ''

# Failure classification summary
$learnerTool  = @($Results | Where-Object { $_.Status -eq 'FAIL' -and $_.Category -eq 'learner-tool' }).Count
$learnerCfg   = @($Results | Where-Object { $_.Status -eq 'FAIL' -and $_.Category -eq 'learner-config' }).Count
$credential   = @($Results | Where-Object { $_.Status -eq 'FAIL' -and $_.Category -eq 'credential' }).Count
$instructor   = @($Results | Where-Object { $_.Status -eq 'FAIL' -and $_.Category -eq 'instructor-side' }).Count

if ($failCount -gt 0) {
    Write-Host 'Failure classification:' -ForegroundColor Yellow
    if ($learnerTool -gt 0)  { Write-Host "  Learner (tool)       : $learnerTool  -> run .\scripts\Install-Tools.ps1" -ForegroundColor Yellow }
    if ($learnerCfg -gt 0)   { Write-Host "  Learner (config)     : $learnerCfg   -> fix .env / .gitignore" -ForegroundColor Yellow }
    if ($credential -gt 0)   { Write-Host "  Credential/connection: $credential   -> re-run New-SnowflakeConnection or Learner-Login" -ForegroundColor Yellow }
    if ($instructor -gt 0)   { Write-Host "  Instructor-side      : $instructor   -> escalate (RBAC / Key Vault / Storage)" -ForegroundColor Yellow }
    Write-Host ''
}

# Overall status
$overallStatus = if ($failCount -gt 0) {
    'NOT READY'
} elseif ($warnCount -gt 0) {
    'READY (with warnings)'
} else {
    'READY'
}

Write-Host "  Status: $overallStatus" -ForegroundColor $(if ($failCount -gt 0) { 'Red' } elseif ($warnCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "  VM: $vmName  User: $vmUser" -ForegroundColor DarkGray
if ($LearnerPrefix) {
    Write-Host "  Learner: $LearnerPrefix" -ForegroundColor DarkGray
}
Write-Host ''

# ------------------------------------------------------------------
# Report (always written)
# ------------------------------------------------------------------

$markdownPath = "$ReportPath.md"
$jsonPath     = "$ReportPath.json"

$reportDir = Split-Path -Parent $markdownPath
if ($reportDir -and -not (Test-Path $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# VM Readiness Report')
$lines.Add('')
$lines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$lines.Add("VM host: $vmName")
$lines.Add("User: $vmUser")
if ($LearnerPrefix) {
    $lines.Add("Learner prefix: $LearnerPrefix")
}
$lines.Add("Status: $overallStatus")
$lines.Add('')
$lines.Add('| Phase | Name | Status | Category | Detail | Recommended action |')
$lines.Add('|---|---|---|---|---|---|')
foreach ($item in $Results) {
    $cleanDetail = ($item.Detail -replace '\|', '/') -replace '\s+', ' '
    if ($cleanDetail.Length -gt 80) { $cleanDetail = $cleanDetail.Substring(0, 80) }
    $cleanAction = ($item.RecommendedAction -replace '\|', '/') -replace '\s+', ' '
    if ($cleanAction.Length -gt 80) { $cleanAction = $cleanAction.Substring(0, 80) }
    $lines.Add(("| {0} | {1} | {2} | {3} | {4} | {5} |" -f $item.Phase, $item.Name, $item.Status, $item.Category, $cleanDetail, $cleanAction))
}
$lines.Add('')
$lines.Add("PASS: $passCount | FAIL: $failCount | WARN: $warnCount | SKIP: $skipCount")
if ($failCount -gt 0) {
    $lines.Add('')
    $lines.Add('Failure classification:')
    $lines.Add("- Learner (tool): $learnerTool")
    $lines.Add("- Learner (config): $learnerCfg")
    $lines.Add("- Credential/connection: $credential")
    $lines.Add("- Instructor-side: $instructor")
}

$lines | Set-Content -Path $markdownPath -Encoding utf8

$reportObject = [PSCustomObject]@{
    generated   = (Get-Date -Format 'yyyy-MM-ddTHH:mm:ss')
    vm          = $vmName
    user        = $vmUser
    learner     = $LearnerPrefix
    status      = $overallStatus
    summary     = @{
        PASS = $passCount
        FAIL = $failCount
        WARN = $warnCount
        SKIP = $skipCount
    }
    failures    = @{
        learnerTool  = $learnerTool
        learnerConfig = $learnerCfg
        credential   = $credential
        instructorSide = $instructor
    }
    results     = $Results
}
$reportObject | ConvertTo-Json -Depth 4 | Set-Content -Path $jsonPath -Encoding utf8

Write-Host "Report: $markdownPath" -ForegroundColor DarkGray
Write-Host "Report: $jsonPath" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# Final message
# ------------------------------------------------------------------

if ($failCount -gt 0) {
    Write-Host "Status: $overallStatus - fix FAIL items before starting labs" -ForegroundColor Red
    Write-Host ''
    Write-Host 'Recommended next steps (in order):' -ForegroundColor Cyan
    $failures = $Results | Where-Object { $_.Status -eq 'FAIL' -and $_.RecommendedAction }
    $seen = @{}
    foreach ($f in $failures) {
        if (-not $seen[$f.RecommendedAction]) {
            Write-Host "  -> $($f.RecommendedAction)" -ForegroundColor Cyan
            $seen[$f.RecommendedAction] = $true
        }
    }
    exit 1
} elseif ($warnCount -gt 0) {
    Write-Host "Status: $overallStatus - review WARN items" -ForegroundColor Yellow
    exit 0
} else {
    Write-Host 'Ready for Day 1' -ForegroundColor Green
    exit 0
}
