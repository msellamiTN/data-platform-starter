#requires -version 5.1
<#
.SYNOPSIS
    Self-paced lab validator — "Check my progress" dispatcher.
.DESCRIPTION
    Dispatches to a module's validate.ps1, runs individual tasks or all tasks,
    shows coloured PASS/FAIL with remediation hints, and optionally writes a
    markdown report. Designed for student self-paced use.
.PARAMETER Module
    Module number (0-14).
.PARAMETER Task
    Specific task number to validate.
.PARAMETER All
    Validate all tasks for the module.
.PARAMETER Report
    Write a markdown report to student-track/_reports/.
.PARAMETER WorkspaceRoot
    Optional workspace root path. Defaults to $HOME\Data2AI-Labs.
.EXAMPLE
    .\SelfPacedLab.ps1 -Module 0 -All
.EXAMPLE
    .\SelfPacedLab.ps1 -Module 1 -Task 3
.EXAMPLE
    .\SelfPacedLab.ps1 -Module 5 -All -Report
.NOTES
    Exit code 0 = all tasks passed, 1 = at least one failure.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(0, 14)]
    [int]$Module,

    [int]$Task,

    [switch]$All,

    [switch]$Report,

    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'

# ── Resolve repo root ────────────────────────────────────────────────────────
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path

# ── Resolve module folder ────────────────────────────────────────────────────
$moduleNum = '{0:00}' -f $Module
$modulePattern = "module-$moduleNum-*"
$moduleDirs = Get-ChildItem -Path (Join-Path $repoRoot 'student-track') -Directory -Filter $modulePattern -ErrorAction SilentlyContinue

if (-not $moduleDirs -or $moduleDirs.Count -eq 0) {
    Write-Host "No module folder found matching '$modulePattern' in student-track/." -ForegroundColor Red
    Write-Host "Module M$Module may not be created yet." -ForegroundColor Yellow
    exit 1
}
if ($moduleDirs.Count -gt 1) {
    Write-Host "Multiple module folders found: $($moduleDirs.Name -join ', ')" -ForegroundColor Red
    exit 1
}
$moduleDir = $moduleDirs[0].FullName
$moduleName = $moduleDirs[0].Name

# ── Resolve workspace ────────────────────────────────────────────────────────
if (-not $WorkspaceRoot) {
    $WorkspaceRoot = Join-Path $HOME 'Data2AI-Labs'
}
$moduleWorkspace = Join-Path $WorkspaceRoot $moduleName

if (-not (Test-Path $moduleWorkspace)) {
    Write-Host "Workspace not found: $moduleWorkspace" -ForegroundColor Red
    Write-Host "Run: .\scripts\New-StudentWorkspace.ps1 -Module $Module -Initials <YOUR_INITIALS>" -ForegroundColor Yellow
    exit 1
}

# ── Load .env ────────────────────────────────────────────────────────────────
$envFile = Join-Path $repoRoot '.env'
if (Test-Path $envFile) {
    foreach ($line in (Get-Content $envFile)) {
        if ($line -match '^\s*([^#]\S+)\s*=\s*(?:''|"|)(.*?)\s*$') {
            [Environment]::SetEnvironmentVariable($matches[1].Trim(), $matches[2].Trim(), 'Process')
        }
    }
}
if (-not $env:ENVIRONMENT) { $env:ENVIRONMENT = 'DEV' }
if (-not $env:TEAM) { $env:TEAM = 'DATA_ENG' }

# ── Set encoding ─────────────────────────────────────────────────────────────
$env:SNOWFLAKE_CLI_ENCODING_FILE_IO   = 'utf-8'
$env:SNOWFLAKE_CLI_ENCODING_SUBPROCESS = 'utf-8'
$env:SNOWFLAKE_CLI_ENCODING_STDOUT     = 'utf-8'
# DO NOT set PYTHONUTF8=1: it makes Python decode subprocess output (e.g. icacls)
# as UTF-8, which crashes on French Windows where icacls emits cp1252 bytes.

# ── Locate validate.ps1 ──────────────────────────────────────────────────────
$validateScript = Join-Path $moduleDir 'validate.ps1'
if (-not (Test-Path $validateScript)) {
    Write-Host "validate.ps1 not found in $moduleName" -ForegroundColor Red
    Write-Host "Expected: $validateScript" -ForegroundColor Yellow
    exit 1
}

# ── Set workspace context for the validator ──────────────────────────────────
$env:STUDENT_WORKSPACE = $moduleWorkspace
$env:STUDENT_MODULE_DIR = $moduleDir
$env:STUDENT_MODULE_NUM = $moduleNum
$env:STUDENT_INITIALS = if (Test-Path (Join-Path $moduleWorkspace '.student-workspace.json')) {
    (Get-Content (Join-Path $moduleWorkspace '.student-workspace.json') -Raw | ConvertFrom-Json).initials
} else { 'STUDENT' }

# ── Dispatch ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Module M$Module - $moduleName" -ForegroundColor Cyan
Write-Host "Workspace: $moduleWorkspace" -ForegroundColor DarkGray
Write-Host ""

$validatorParameters = @{}
if ($All) {
    $validatorParameters.All = $true
} elseif ($Task) {
    $validatorParameters.Task = $Task
} else {
    Write-Host "Usage: .\SelfPacedLab.ps1 -Module $Module -Task N  |  -All" -ForegroundColor Yellow
    Write-Host "Add -Report to generate a markdown report." -ForegroundColor DarkGray
    exit 0
}
if ($Report) { $validatorParameters.Report = $true }

Push-Location $moduleWorkspace
try {
    & $validateScript @validatorParameters
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $exitCode
