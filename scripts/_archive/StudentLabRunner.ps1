<#
.SYNOPSIS
    Execute a Data2AI training lab like a student would, record every step and produce a report.

.PARAMETER Day
    Day folder under courses/ (e.g. "day-00").

.PARAMETER Module
    Module folder name (e.g. "module-00-setup").

.PARAMETER StopOnError
    Stop the whole run when a step fails (default: true).
#>
param(
    [Parameter(Mandatory)]
    [string]$Day,

    [Parameter(Mandatory)]
    [string]$Module,

    [bool]$StopOnError = $true
)

$ErrorActionPreference = "Stop"

$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
Set-Location $repoRoot

# ---------------------------------------------------------------------------------------------------------------------------------------------
# Load shared secrets from 00-bootstrap terraform.tfvars (gitignored)
# ---------------------------------------------------------------------------------------------------------------------------------------------
$envFile = "$repoRoot\.env"
if (-not (Test-Path $envFile)) {
    throw "Cannot find $envFile. Copy .env.example to .env and fill it in."
}
foreach ($line in (Get-Content $envFile)) {
    if ($line -match '^\s*([^#]\S+)\s*=\s*(?:''|"|)(.*?)\s*$') {
        [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
    }
}

$env:SNOWFLAKE_CLI_ENCODING_FILE_IO   = 'utf-8'
$env:SNOWFLAKE_CLI_ENCODING_SUBPROCESS = 'utf-8'
$env:SNOWFLAKE_CLI_ENCODING_STDOUT     = 'utf-8'
# DO NOT set PYTHONUTF8=1: it makes Python decode subprocess output (e.g. icacls)
# as UTF-8, which crashes on French Windows where icacls emits cp1252 bytes.

$env:PATH = "$repoRoot\tools\tf-bin;$env:PATH"

function Reset-SnowflakeConnections {
    $configFile = "$env:USERPROFILE\.snowflake\config.toml"
    if (-not (Test-Path $configFile)) { return }
    $content = Get-Content $configFile -Raw
    $options = [System.Text.RegularExpressions.RegexOptions]::Multiline -bor [System.Text.RegularExpressions.RegexOptions]::Singleline
    $newContent = [regex]::Replace($content, '^\[connections\.admin\].*?(?=^\[|\z)', '', $options)
    $newContent = [regex]::Replace($newContent, '^\[connections\.terraform_svc\].*?(?=^\[|\z)', '', $options)
    if ($newContent -ne $content) {
        Copy-Item $configFile "$configFile.bak" -Force
        Set-Content -Path $configFile -Value $newContent -NoNewline
    }
}

Reset-SnowflakeConnections

# ---------------------------------------------------------------------------------------------------------------------------------------------
# Locate the lab and parse steps
# ---------------------------------------------------------------------------------------------------------------------------------------------
$labPath = "$repoRoot\courses\$Day\$Module\lab.md"
if (-not (Test-Path $labPath)) {
    throw "Lab not found: $labPath"
}
$labText = Get-Content $labPath -Raw

# Split the markdown by level-2 or level-3 headings to get steps
$stepPattern = '^(?:#{2,3})\s+(.*?)(?=\r?\n)'
$stepMatches = [regex]::Matches($labText, $stepPattern, 'Multiline')

$steps = @()
for ($i = 0; $i -lt $stepMatches.Count; $i++) {
    $title = $stepMatches[$i].Groups[1].Value.Trim()
    $start = $stepMatches[$i].Index + $stepMatches[$i].Length
    $end = if ($i -lt $stepMatches.Count - 1) { $stepMatches[$i + 1].Index } else { $labText.Length }
    $body = $labText.Substring($start, $end - $start)
    $steps += @{ Title = $title; Body = $body }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------------------------------------------------------------------------
function Resolve-Placeholders([string]$Code) {
    $Code = $Code -replace '<snowflake-organization>', $env:SNOWFLAKE_ORGANIZATION
    $Code = $Code -replace '<snowflake-account>', $env:SNOWFLAKE_ACCOUNT
    $Code = $Code -replace '<SNOWFLAKE_PASSWORD>', $env:SNOWFLAKE_ADMIN_PASSWORD
    $Code = $Code -replace '<snowflake-organization>-<snowflake-account>', "$($env:SNOWFLAKE_ORGANIZATION)-$($env:SNOWFLAKE_ACCOUNT)"
    $Code = $Code -replace '<MOT_DE_PASSE>', $env:SNOWFLAKE_ADMIN_PASSWORD
    $Code = $Code -replace '<SNOWFLAKE_ADMIN_CONNECTION>', $env:SNOWFLAKE_ADMIN_CONNECTION
    $Code = $Code -replace '<SNOWFLAKE_TERRAFORM_CONNECTION>', $env:SNOWFLAKE_TERRAFORM_CONNECTION
    $Code = $Code -replace '<SNOWFLAKE_ADMIN_USER>', $env:SNOWFLAKE_ADMIN_USER
    $Code = $Code -replace '<SNOWFLAKE_TERRAFORM_USER>', $env:SNOWFLAKE_TERRAFORM_USER
    $Code = $Code -replace '<SNOWFLAKE_ROLE>', $env:SNOWFLAKE_ROLE
    $Code = $Code -replace '<PRIVATE_KEY_PATH>', $env:PRIVATE_KEY_PATH
    $Code = $Code -replace '<DEPLOYMENT_MODE>', $env:DEPLOYMENT_MODE
    $Code = $Code -replace '<ARM_SUBSCRIPTION_ID>', $env:ARM_SUBSCRIPTION_ID
    $Code = $Code -replace '<ARM_CLIENT_ID>', $env:ARM_CLIENT_ID
    $Code = $Code -replace '<ARM_CLIENT_SECRET>', $env:ARM_CLIENT_SECRET
    $Code = $Code -replace '<ARM_TENANT_ID>', $env:ARM_TENANT_ID
    $Code = $Code -replace '<RESOURCE_GROUP_NAME>', $env:RESOURCE_GROUP_NAME
    $Code = $Code -replace '<STORAGE_ACCOUNT_NAME>', $env:STORAGE_ACCOUNT_NAME
    $Code = $Code -replace '<TEAM>', $env:TEAM
    # The bundled windows_386 terraform binary only accepts -option value, not -option=value
    $lines = $Code -split "`r?`n"
    $lines = $lines | ForEach-Object {
        $line = $_
        if ($line -match '^\s*terraform(\.exe)?\s') {
            $line = $line -replace ' -([-\w]+)="([^"]+)"', ' -$1 "$2"'
            $line = $line -replace ' -([-\w]+)=([^"\s]+)', ' -$1 $2'
        }
        $line
    }
    $Code = $lines -join "`r`n"
    # Keep other placeholders visible so they appear in the log
    return $Code
}

function Invoke-LabStep([hashtable]$Step) {
    $stepOutput = @()
    $stepPassed = $true
    $stepError = $null

    # Find all PowerShell code blocks in the step body
    $blocks = [regex]::Matches($Step.Body, '```powershell\s*\r?\n(.*?)\r?\n```', 'Singleline')

    if ($blocks.Count -eq 0) {
        return @{ Passed = $true; Output = @("No PowerShell code block in this step.") }
    }

    $sessionScript = @()
    foreach ($block in $blocks) {
        $rawCode = $block.Groups[1].Value
        # Skip editor / browser open commands
        $filtered = ($rawCode -split "`r?`n" | Where-Object { $_ -notmatch '^\s*code\s+' }) -join "`r`n"
        if (-not $filtered.Trim()) { continue }
        $sessionScript += Resolve-Placeholders $filtered
    }

    if ($sessionScript.Count -eq 0) {
        return @{ Passed = $true; Output = @("All code blocks were non-executable (e.g. `code` commands).") }
    }

    $scriptText = $sessionScript -join "`r`n`r`n"
    $tempFile = Join-Path $env:TEMP "Lab-$($Module)-$([Guid]::NewGuid()).ps1"
    Set-Content -Path $tempFile -Value $scriptText -NoNewline

    # Run the step in its own PowerShell session so `cd` state and variables do not leak
    $outFile = "$tempFile.out"
    $errFile = "$tempFile.err"

    $proc = Start-Process -FilePath "powershell.exe" `
        -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $tempFile) `
        -WorkingDirectory $repoRoot `
        -Wait -PassThru `
        -RedirectStandardOutput $outFile `
        -RedirectStandardError $errFile

    $stdOut = if (Test-Path $outFile) { Get-Content $outFile -Raw } else { '' }
    $stdErr = if (Test-Path $errFile) { Get-Content $errFile -Raw } else { '' }

    Remove-Item $tempFile, $outFile, $errFile -ErrorAction SilentlyContinue

    $stepOutput += "--- code ---"
    $stepOutput += $scriptText
    $stepOutput += "--- exit code: $($proc.ExitCode) ---"
    $stepOutput += "--- stdout ---"
    $stepOutput += $stdOut
    if ($stdErr) {
        $stepOutput += "--- stderr ---"
        $stepOutput += $stdErr
    }

    $hasWarnings = ($stdOut + $stdErr) -match 'Warning[:\s]|warning[:\s]|WARN'
    $hasErrors   = ($proc.ExitCode -ne 0) -or ($stdOut + $stdErr) -match '\bError:'

    if ($hasErrors) {
        $stepPassed = $false
        $stepError = if ($stdErr) { ($stdErr -split "`r?`n")[0] } else { "Exit code $($proc.ExitCode)." }
    } elseif ($hasWarnings) {
        $stepPassed = $false
        $stepError = 'Warning output detected.'
    }

    return @{ Passed = $stepPassed; Error = $stepError; Output = $stepOutput }
}

# ---------------------------------------------------------------------------------------------------------------------------------------------
# Run the lab
# ---------------------------------------------------------------------------------------------------------------------------------------------
$report = [System.Collections.Generic.List[string]]::new()
$report.Add("# Student Simulation Report - $Day / $Module")
$report.Add("")
$report.Add("Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$report.Add("")
$report.Add("| Step | Result | Error |")
$report.Add("|------|--------|-------|")

$overallPass = $true
$results = @()

foreach ($step in $steps) {
    Write-Host "Running step: $($step.Title)" -ForegroundColor Cyan
    $res = Invoke-LabStep $step
    $status = if ($res.Passed) { 'PASS' } else { 'FAIL' }
    $report.Add("| $($step.Title) | $status | $(if ($res.Error) { $res.Error } else { '-' }) |")
    $results += @{ Title = $step.Title; Result = $res }
    if (-not $res.Passed) {
        $overallPass = $false
        if ($StopOnError) { break }
    }
}

$report.Add("")
$report.Add("## Overall: $(if ($overallPass) { 'PASS' } else { 'FAIL' })")
$report.Add("")

# Append detailed logs
foreach ($r in $results) {
    $report.Add("---")
    $report.Add("## $($r.Title)")
    $report.Add("")
    $report.AddRange([string[]]$r.Result.Output)
    $report.Add("")
}

$reportPath = "$repoRoot\docs\student-simulation-report-$Day-$Module.md"
$report | Set-Content -Path $reportPath -Encoding UTF8

Write-Host ""
Write-Host "Report written to: $reportPath" -ForegroundColor Green
Write-Host "Overall: $(if ($overallPass) { 'PASS' } else { 'FAIL' })" -ForegroundColor $(if ($overallPass) { 'Green' } else { 'Red' })

if (-not $overallPass -and $StopOnError) { exit 1 }
