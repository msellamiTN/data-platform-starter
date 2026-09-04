#requires -version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = "Continue"

$results = @()

function Write-Header {
    param([string]$Title)

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
}

function Test-Tool {
    param(
        [string]$Name,
        [string]$Command,
        [string]$Arguments
    )

    Write-Host ""
    Write-Host "Checking $Name..." -ForegroundColor Yellow

    $cmd = Get-Command $Command -ErrorAction SilentlyContinue

    if ($null -eq $cmd) {

        Write-Host "[FAIL] $Name not found" -ForegroundColor Red

        $script:results += [PSCustomObject]@{
            Tool    = $Name
            Status  = "FAIL"
            Details = "Command not found"
            Path    = ""
        }

        return
    }

    try {

        $output = & $Command $Arguments 2>&1

        $firstLine = $output |
            Where-Object { $_ -and $_.ToString().Trim().Length -gt 0 } |
            Select-Object -First 1

        Write-Host "[OK] $Name" -ForegroundColor Green
        Write-Host "     Path    : $($cmd.Source)" -ForegroundColor DarkGray
        Write-Host "     Version : $firstLine" -ForegroundColor DarkGray

        $script:results += [PSCustomObject]@{
            Tool    = $Name
            Status  = "OK"
            Details = [string]$firstLine
            Path    = $cmd.Source
        }
    }
    catch {

        Write-Host "[FAIL] $Name" -ForegroundColor Red
        Write-Host "       $($_.Exception.Message)" -ForegroundColor DarkGray

        $script:results += [PSCustomObject]@{
            Tool    = $Name
            Status  = "FAIL"
            Details = $_.Exception.Message
            Path    = $cmd.Source
        }
    }
}

function Test-PathExists {
    param(
        [string]$Name,
        [string]$Path
    )

    Write-Host ""
    Write-Host "Checking $Name..." -ForegroundColor Yellow

    if (Test-Path $Path) {

        Write-Host "[OK] $Name" -ForegroundColor Green
        Write-Host "     $Path" -ForegroundColor DarkGray

        $script:results += [PSCustomObject]@{
            Tool    = $Name
            Status  = "OK"
            Details = "Path exists"
            Path    = $Path
        }
    }
    else {

        Write-Host "[FAIL] $Name" -ForegroundColor Red

        $script:results += [PSCustomObject]@{
            Tool    = $Name
            Status  = "FAIL"
            Details = "Path not found"
            Path    = $Path
        }
    }
}

Write-Header "TERRAFORM & SNOWFLAKE LAB - ENVIRONMENT CHECK"

# ============================================================
# SYSTEM
# ============================================================

Write-Header "SYSTEM CHECKS"

Write-Host ""
Write-Host "PowerShell version:" -ForegroundColor Yellow
$PSVersionTable.PSVersion

Write-Host ""
Write-Host "Operating system architecture:" -ForegroundColor Yellow
if ([Environment]::Is64BitOperatingSystem) {
    Write-Host "[OK] 64-bit Windows" -ForegroundColor Green
}
else {
    Write-Host "[FAIL] 32-bit Windows" -ForegroundColor Red
}

# ============================================================
# REQUIRED TOOLS
# ============================================================

Write-Header "REQUIRED TOOLS"

Test-Tool `
    -Name "Git" `
    -Command "git" `
    -Arguments "--version"

Test-Tool `
    -Name "OpenSSL" `
    -Command "openssl" `
    -Arguments "version"

Test-Tool `
    -Name "Terraform" `
    -Command "terraform" `
    -Arguments "version"

Test-Tool `
    -Name "Python" `
    -Command "python" `
    -Arguments "--version"

Test-Tool `
    -Name "Snowflake CLI" `
    -Command "snow" `
    -Arguments "--version"

Test-Tool `
    -Name "Azure CLI" `
    -Command "az" `
    -Arguments "version"

Test-Tool `
    -Name "TFLint" `
    -Command "tflint" `
    -Arguments "--version"

Test-Tool `
    -Name "VS Code" `
    -Command "code" `
    -Arguments "--version"

# ============================================================
# EXPECTED INSTALLATION DIRECTORIES
# ============================================================

Write-Header "INSTALLATION PATHS"

Test-PathExists `
    -Name "Terraform installation directory" `
    -Path "C:\tools\tf-bin"

Test-PathExists `
    -Name "TFLint installation directory" `
    -Path "C:\tools\tflint-bin"

Test-PathExists `
    -Name "Git installation directory" `
    -Path "C:\Program Files\Git"

# ============================================================
# PYTHON / SNOWFLAKE
# ============================================================

Write-Header "PYTHON / SNOWFLAKE CHECKS"

if (Get-Command python -ErrorAction SilentlyContinue) {

    try {

        $pythonVersion = & python --version 2>&1

        Write-Host "[OK] Python detected: $pythonVersion" `
            -ForegroundColor Green

        $pythonExecutable = `
            (Get-Command python).Source

        Write-Host "     Executable: $pythonExecutable" `
            -ForegroundColor DarkGray
    }
    catch {

        Write-Host "[FAIL] Python execution failed" `
            -ForegroundColor Red
    }
}
else {

    Write-Host "[FAIL] Python not detected" `
        -ForegroundColor Red
}

if (Get-Command python -ErrorAction SilentlyContinue) {

    try {

        $pipVersion = & python -m pip --version 2>&1

        Write-Host "[OK] pip detected" `
            -ForegroundColor Green

        Write-Host "     $pipVersion" `
            -ForegroundColor DarkGray
    }
    catch {

        Write-Host "[FAIL] pip not available" `
            -ForegroundColor Red
    }
}

if (Get-Command snow -ErrorAction SilentlyContinue) {

    try {

        $snowVersion = & snow --version 2>&1

        Write-Host "[OK] Snowflake CLI detected" `
            -ForegroundColor Green

        Write-Host "     $snowVersion" `
            -ForegroundColor DarkGray
    }
    catch {

        Write-Host "[FAIL] Snowflake CLI cannot execute" `
            -ForegroundColor Red
    }
}

# ============================================================
# AZURE
# ============================================================

Write-Header "AZURE CHECKS"

if (Get-Command az -ErrorAction SilentlyContinue) {

    Write-Host "[OK] Azure CLI detected" `
        -ForegroundColor Green

    try {

        $azVersion = `
            & az version 2>&1 |
            ConvertFrom-Json

        Write-Host "     Azure CLI : $($azVersion.'azure-cli')" `
            -ForegroundColor DarkGray
        Write-Host "     Extensions: $($azVersion.extensions)" `
            -ForegroundColor DarkGray
    }
    catch {

        Write-Host "     Version information unavailable" `
            -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-Host "Checking Azure authentication..." `
        -ForegroundColor Yellow

    try {

        $account = az account show 2>$null |
            ConvertFrom-Json

        if ($null -ne $account) {

            Write-Host "[OK] Azure authenticated" `
                -ForegroundColor Green

            Write-Host "     User         : $($account.user.name)" `
                -ForegroundColor DarkGray

            Write-Host "     Subscription : $($account.name)" `
                -ForegroundColor DarkGray

            Write-Host "     Tenant       : $($account.tenantId)" `
                -ForegroundColor DarkGray
        }
    }
    catch {

        Write-Host "[INFO] Azure CLI installed but not authenticated" `
            -ForegroundColor Yellow

        Write-Host "       Run: az login" `
            -ForegroundColor DarkGray
    }
}
else {

    Write-Host "[FAIL] Azure CLI not detected" `
        -ForegroundColor Red
}

# ============================================================
# GIT REPOSITORY
# ============================================================

Write-Header "GIT REPOSITORY CHECK"

$gitRoot = $null

try {

    $gitRoot = git rev-parse --show-toplevel 2>$null
}
catch {}

if ($gitRoot) {

    Write-Host "[OK] Git repository detected" `
        -ForegroundColor Green

    Write-Host "     Root: $gitRoot" `
        -ForegroundColor DarkGray

    try {

        $remote = git remote get-url origin 2>$null

        Write-Host "[OK] Git remote detected" `
            -ForegroundColor Green

        Write-Host "     $remote" `
            -ForegroundColor DarkGray
    }
    catch {

        Write-Host "[INFO] No origin remote configured" `
            -ForegroundColor Yellow
    }

    Write-Host ""
    Write-Host "Git status:" -ForegroundColor Yellow

    git status --short
}
else {

    Write-Host "[FAIL] Current directory is not a Git repository" `
        -ForegroundColor Red
}

# ============================================================
# TERRAFORM PROJECT
# ============================================================

Write-Header "TERRAFORM PROJECT CHECK"

$tfFiles = Get-ChildItem `
    -Path . `
    -Filter "*.tf" `
    -Recurse `
    -File `
    -ErrorAction SilentlyContinue

if ($tfFiles.Count -gt 0) {

    Write-Host "[OK] Terraform files detected: $($tfFiles.Count)" `
        -ForegroundColor Green

    $tfFiles |
        ForEach-Object {
            Write-Host "     $($_.FullName)" `
                -ForegroundColor DarkGray
        }
}
else {

    Write-Host "[FAIL] No Terraform files found" `
        -ForegroundColor Red
}

# ============================================================
# TERRAFORM VALIDATION
# ============================================================

Write-Header "TERRAFORM VALIDATION"

if (Get-Command terraform -ErrorAction SilentlyContinue) {

    Write-Host "Running terraform validate..." `
        -ForegroundColor Yellow

    try {

        terraform validate

        if ($LASTEXITCODE -eq 0) {

            Write-Host "[OK] Terraform configuration is valid" `
                -ForegroundColor Green
        }
        else {

            Write-Host "[FAIL] terraform validate returned code $LASTEXITCODE" `
                -ForegroundColor Red
        }
    }
    catch {

        Write-Host "[FAIL] terraform validate could not execute" `
            -ForegroundColor Red
    }
}

# ============================================================
# TFLINT
# ============================================================

Write-Header "TFLINT CHECK"

if (Get-Command tflint -ErrorAction SilentlyContinue) {

    if (Test-Path ".\.tflint.hcl") {

        Write-Host "[OK] .tflint.hcl detected" `
            -ForegroundColor Green
    }
    else {

        Write-Host "[INFO] .tflint.hcl not found" `
            -ForegroundColor Yellow
    }
}

# ============================================================
# VS CODE EXTENSIONS
# ============================================================

Write-Header "VS CODE EXTENSIONS"

if (Get-Command code -ErrorAction SilentlyContinue) {

    $extensions = @(
        "HashiCorp.terraform",
        "ms-azuretools.vscode-azureterraform",
        "ms-python.python",
        "redhat.vscode-yaml",
        "shd101wyy.markdown-preview-enhanced"
    )

    $installedExtensions = `
        code --list-extensions 2>$null

    foreach ($extension in $extensions) {

        if ($installedExtensions -contains $extension) {

            Write-Host "[OK] $extension" `
                -ForegroundColor Green
        }
        else {

            Write-Host "[FAIL] $extension" `
                -ForegroundColor Red
        }
    }
}

# ============================================================
# FINAL SUMMARY
# ============================================================

Write-Header "FINAL SUMMARY"

$failed = $results |
    Where-Object { $_.Status -eq "FAIL" }

$passed = $results |
    Where-Object { $_.Status -eq "OK" }

Write-Host ""
Write-Host "Checks passed : $($passed.Count)" `
    -ForegroundColor Green

Write-Host "Checks failed : $($failed.Count)" `
    -ForegroundColor $(if ($failed.Count -eq 0) { "Green" } else { "Red" })

if ($failed.Count -gt 0) {

    Write-Host ""
    Write-Host "FAILED CHECKS:" `
        -ForegroundColor Red

    foreach ($item in $failed) {

        Write-Host "  - $($item.Tool): $($item.Details)" `
            -ForegroundColor Red
    }

    Write-Host ""
    Write-Host "Environment status: NOT READY" `
        -ForegroundColor Red

    exit 1
}
else {

    Write-Host ""
    Write-Host "Environment status: READY" `
        -ForegroundColor Green

    Write-Host ""
    Write-Host "The Terraform & Snowflake lab environment is ready." `
        -ForegroundColor Green

    exit 0
}