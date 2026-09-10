[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Report
)
$ErrorActionPreference = 'Stop'
$ws = if ($env:STUDENT_WORKSPACE) { $env:STUDENT_WORKSPACE } else { '.' }
Write-Host ''
Write-Host '== M00 - Setup validation' -ForegroundColor Cyan
$tools = @('git','terraform','az','snow')
$fail = 0
foreach ($t in $tools) {
    if (Get-Command $t -ErrorAction SilentlyContinue) {
        Write-Host "  [PASS] $t" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $t manquant" -ForegroundColor Red
        $fail++
    }
}
if ($fail -gt 0) { exit 1 }
Write-Host '  Tous les outils obligatoires sont presents.' -ForegroundColor Green