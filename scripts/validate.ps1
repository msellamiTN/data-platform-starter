<#
.SYNOPSIS
    Local validation script for the data-platform-starter project (Windows).

.DESCRIPTION
    Runs terraform fmt, validate and tflint on all environment roots.
    Nothing is deployed. No secret is read or displayed.

.EXAMPLE
    .\scripts\validate.ps1
#>

$ErrorActionPreference = 'Continue'

$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$environments = Join-Path $root 'environments'

if (-not (Test-Path $environments)) {
    Write-Host '[FAIL] environments/ directory not found' -ForegroundColor Red
    exit 1
}

$hasFailures = $false

Write-Host '== terraform fmt -check -recursive ==' -ForegroundColor Cyan
& terraform fmt -check -recursive $environments
if ($LASTEXITCODE -ne 0) {
    $hasFailures = $true
    Write-Host '[FAIL] Formatting issues detected' -ForegroundColor Red
} else {
    Write-Host '[PASS] Formatting is clean' -ForegroundColor Green
}

foreach ($envDir in (Get-ChildItem $environments -Directory)) {
    $envName = $envDir.Name
    $tfFiles = Get-ChildItem $envDir.FullName -Filter '*.tf' -File -ErrorAction SilentlyContinue

    if (-not $tfFiles) {
        Write-Host "[SKIP] $envName : no .tf files yet" -ForegroundColor DarkGray
        continue
    }

    Write-Host "== $envName : terraform validate ==" -ForegroundColor Cyan
    Push-Location $envDir.FullName
    try {
        & terraform init -backend=false -input=false -no-color 2>&1 | Out-Null
        & terraform validate -no-color
        if ($LASTEXITCODE -ne 0) {
            $hasFailures = $true
            Write-Host "[FAIL] $envName : validation failed" -ForegroundColor Red
        } else {
            Write-Host "[PASS] $envName : validation succeeded" -ForegroundColor Green
        }
    } finally {
        Pop-Location
    }
}

if (Get-Command tflint -ErrorAction SilentlyContinue) {
    Write-Host '== tflint ==' -ForegroundColor Cyan
    & tflint -c (Join-Path $root '.tflint.hcl') $environments
    if ($LASTEXITCODE -ne 0) {
        $hasFailures = $true
        Write-Host '[WARN] tflint reported issues' -ForegroundColor Yellow
    } else {
        Write-Host '[PASS] tflint is clean' -ForegroundColor Green
    }
} else {
    Write-Host '[SKIP] tflint not installed' -ForegroundColor DarkGray
}

if ($hasFailures) {
    Write-Host ''
    Write-Host 'Validation: FAILED' -ForegroundColor Red
    exit 1
}

Write-Host ''
Write-Host 'Validation: PASSED' -ForegroundColor Green
exit 0
