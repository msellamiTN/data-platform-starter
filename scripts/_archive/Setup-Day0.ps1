#requires -version 5.1
<#
.SYNOPSIS
    Preflight non destructif du Jour 0 pour Windows.
.DESCRIPTION
    Verifie le poste, la configuration locale et, sauf demande contraire, une
    connexion Snowflake. Le script n'installe rien, ne fait aucun git pull, ne
    cree aucun utilisateur et ne modifie aucune policy.
.PARAMETER AccessScenario
    SANDBOX ou TRIAL.
.PARAMETER Connection
    Connexion Snowflake CLI a tester.
.PARAMETER SkipSnowflake
    Ignore le test distant pour verifier uniquement le poste local.
#>
[CmdletBinding()]
param(
    [ValidateSet('SANDBOX', 'TRIAL')]
    [string]$AccessScenario = 'SANDBOX',
    [string]$Connection = 'terraform_svc',
    [switch]$SkipSnowflake
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path "$PSScriptRoot\..").Path
$results = [System.Collections.Generic.List[object]]::new()

function Add-Result([string]$Name, [bool]$Passed, [string]$Detail, [bool]$Required = $true) {
    $results.Add([PSCustomObject]@{ Name = $Name; Passed = $Passed; Detail = $Detail; Required = $Required })
}

function Test-Tool([string]$Name, [string[]]$Arguments) {
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        Add-Result $Name $false 'Absent du PATH'
        return
    }
    $commandOutput = @(& $Name @Arguments 2>&1)
    $commandExitCode = $LASTEXITCODE
    $detail = if ($commandOutput.Count -gt 0) { [string]$commandOutput[0] } else { 'Commande disponible' }
    Add-Result $Name ($commandExitCode -eq 0) $detail
}

Write-Host 'Day 0 - preflight non destructif'
Write-Host "Scenario: $AccessScenario"
Write-Host "Repository: $repoRoot"

Test-Tool 'git' @('--version')
Test-Tool 'terraform' @('version')
Test-Tool 'snow' @('--version')

$editorAvailable = $null -ne (Get-Command code -ErrorAction SilentlyContinue)
Add-Result 'VS Code' $editorAvailable $(if ($editorAvailable) { 'Disponible' } else { 'Optionnel; utilisez un autre editeur' }) $false

$envExample = Join-Path $repoRoot '.env.example'
$envFile = Join-Path $repoRoot '.env'
$gitignore = Join-Path $repoRoot '.gitignore'
Add-Result '.env.example' (Test-Path $envExample) 'Template public de configuration'
Add-Result '.gitignore' (Test-Path $gitignore) 'Protection locale des secrets et artefacts'
Add-Result '.env local' (Test-Path $envFile) 'Copiez .env.example vers .env puis remplacez les placeholders'

if (Test-Path $envFile) {
    $envText = Get-Content $envFile -Raw
    Add-Result 'Configuration completee' ($envText -notmatch '<[^>]+>') 'Aucun placeholder <...> ne doit rester'
}

if (Get-Command git -ErrorAction SilentlyContinue) {
    & git -C $repoRoot check-ignore .env *> $null
    Add-Result '.env ignore par Git' ($LASTEXITCODE -eq 0) 'Le fichier local ne doit jamais etre suivi'
    & git -C $repoRoot check-ignore secrets/probe.token *> $null
    Add-Result 'secrets/ ignore par Git' ($LASTEXITCODE -eq 0) 'Les credentials restent hors Git'
}

if (-not $SkipSnowflake) {
    if (Get-Command snow -ErrorAction SilentlyContinue) {
        $previousErrorAction = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        & snow connection test -c $Connection *> $null
        $snowExitCode = $LASTEXITCODE
        $ErrorActionPreference = $previousErrorAction
        Add-Result 'Connexion Snowflake' ($snowExitCode -eq 0) "Connexion '$Connection'"
    } else {
        Add-Result 'Connexion Snowflake' $false 'Snowflake CLI absent'
    }
} else {
    Add-Result 'Connexion Snowflake' $true 'Test distant ignore explicitement' $false
}

Write-Host ''
Write-Host 'Resultats'
foreach ($result in $results) {
    $status = if ($result.Passed) { 'PASS' } elseif ($result.Required) { 'FAIL' } else { 'WARN' }
    Write-Host "[$status] $($result.Name) - $($result.Detail)"
}

$failed = @($results | Where-Object { $_.Required -and -not $_.Passed })
Write-Host ''
if ($failed.Count -eq 0) {
    Write-Host 'Ready for Day 1'
    exit 0
}

Write-Host "Not ready: $($failed.Count) required check(s) failed."
Write-Host 'Open courses/day-00/module-00-setup/troubleshooting.md and rerun this script.'
exit 1
