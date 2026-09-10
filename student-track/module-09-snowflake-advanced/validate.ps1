[CmdletBinding()]
param(
    [switch]$All,
    [switch]$Report
)
$ErrorActionPreference = 'Stop'
$ws = if ($env:STUDENT_WORKSPACE) { $env:STUDENT_WORKSPACE } else { '.' }
if (-not (Test-Path $ws)) { throw "Workspace introuvable : $ws" }
Push-Location $ws
try {
    Write-Host ''
    Write-Host '== Terraform validation' -ForegroundColor Cyan
    $tfFiles = Get-ChildItem -Recurse -Filter '*.tf' -File
    if (-not $tfFiles) {
        Write-Host '  [FAIL] Aucun fichier .tf trouvÃ©. CrÃ©ez d\'abord votre configuration.' -ForegroundColor Red
        exit 1
    }
    & terraform fmt -recursive -check
    if ($LASTEXITCODE -ne 0) { throw 'terraform fmt a Ã©chouÃ©' }
    & terraform init -backend=false
    if ($LASTEXITCODE -ne 0) { throw 'terraform init a Ã©chouÃ©' }
    & terraform validate
    if ($LASTEXITCODE -ne 0) { throw 'terraform validate a Ã©chouÃ©' }
    Write-Host '  [PASS] Fichiers bien formattÃ©s et validÃ©s.' -ForegroundColor Green
} finally {
    Pop-Location
}