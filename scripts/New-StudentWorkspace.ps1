#requires -version 5.1
<#
.SYNOPSIS
    Creates an isolated learner workspace for one module.
.PARAMETER Module
    Module number from 0 to 14.
.PARAMETER Initials
    Two to four uppercase letters.
.PARAMETER WorkspaceRoot
    Destination root. Defaults to $HOME\Data2AI-Labs.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateRange(0, 14)]
    [int]$Module,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Z]{2,4}$')]
    [string]$Initials,
    [string]$WorkspaceRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$moduleNum = '{0:00}' -f $Module
$trackRoot = Join-Path $repoRoot 'student-track'
$moduleDirs = @(Get-ChildItem -Path $trackRoot -Directory -Filter "module-$moduleNum-*" -ErrorAction SilentlyContinue)
if ($moduleDirs.Count -ne 1) {
    throw "Expected one module matching module-$moduleNum-* in $trackRoot; found $($moduleDirs.Count)."
}
$moduleDir = $moduleDirs[0].FullName
$moduleName = $moduleDirs[0].Name
if (-not $WorkspaceRoot) { $WorkspaceRoot = Join-Path $HOME 'Data2AI-Labs' }
$moduleWorkspace = Join-Path $WorkspaceRoot $moduleName
if (Test-Path $moduleWorkspace) {
    throw "Workspace already exists: $moduleWorkspace. Choose another -WorkspaceRoot; no automatic deletion is performed."
}

New-Item -ItemType Directory -Path $moduleWorkspace -Force | Out-Null
$starter = Join-Path $moduleDir 'starter'
if (Test-Path $starter) {
    Copy-Item -Path (Join-Path $starter '*') -Destination $moduleWorkspace -Recurse -Force
}

$gitignore = @(
    '*.tfstate', '*.tfstate.*', '*.tfplan', '*.tfplan.*', '.terraform/', '.terraform.lock.hcl',
    '*.tfvars', '*.tfvars.json', '.env', 'secrets/', '*.p8', '*.pem', '*.key',
    '*.pub', '.student-workspace.json'
)
$gitignore | Set-Content -Path (Join-Path $moduleWorkspace '.gitignore') -Encoding ascii

$metadata = [ordered]@{
    module = $moduleNum
    moduleName = $moduleName
    initials = $Initials
    workspaceRoot = $moduleWorkspace
    repoRoot = $repoRoot
    createdAt = (Get-Date -Format 'o')
    branch = "module-$moduleNum-$Initials"
}
$metadata | ConvertTo-Json -Depth 3 | Set-Content -Path (Join-Path $moduleWorkspace '.student-workspace.json') -Encoding utf8

Push-Location $moduleWorkspace
try {
    & git init --quiet
    if ($LASTEXITCODE -ne 0) { throw 'git init failed.' }
    & git checkout -b "module-$moduleNum-$Initials" --quiet
    if ($LASTEXITCODE -ne 0) { throw 'git branch creation failed.' }
    & git add .
    if ($LASTEXITCODE -ne 0) { throw 'git add failed.' }
    $staged = & git diff --cached --name-only
    if ($staged) {
        & git -c user.name='Data2AI Learner' -c user.email='learner@local.invalid' commit -m "chore(m$moduleNum): scaffold workspace for $Initials" --quiet
        if ($LASTEXITCODE -ne 0) { throw 'Initial commit failed.' }
    }
} finally {
    Pop-Location
}

Write-Host "Workspace ready: $moduleWorkspace"
Write-Host "Guide: $moduleDir\module.md"
Write-Host "Validate: .\scripts\SelfPacedLab.ps1 -Module $Module -All -WorkspaceRoot `"$WorkspaceRoot`""
