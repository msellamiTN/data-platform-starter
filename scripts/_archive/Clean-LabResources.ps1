[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$ProjectRoot = '',
    [string[]]$Exclude = @('admin-fix'),
    [switch]$SkipInit,
    [switch]$AutoApprove
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $ProjectRoot) {
    $ProjectRoot = Join-Path (Join-Path $scriptDir '..') 'project'
}
$ProjectRoot = [System.IO.Path]::GetFullPath($ProjectRoot)

if ($AutoApprove) {
    $ConfirmPreference = 'None'
}

# Charger les variables d'environnement depuis .env (process)
$envFile = Join-Path (Join-Path $scriptDir '..') '.env'
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $line = $_.Trim()
        if ($line -and $line -notmatch '^#') {
            $sep = $line.IndexOf('=')
            if ($sep -gt 0) {
                $key = $line.Substring(0, $sep).Trim()
                $value = $line.Substring($sep + 1).Trim().Trim('"')
                [Environment]::SetEnvironmentVariable($key, $value, 'Process')
            }
        }
    }
}

$stateFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Filter 'terraform.tfstate' -File
$targets = $stateFiles | ForEach-Object { $_.DirectoryName } | Sort-Object -Unique | Where-Object {
    $dir = $_
    $mainTf = Join-Path $dir 'main.tf'
    if (-not (Test-Path $mainTf)) { return $false }
    $relative = $dir.Substring($ProjectRoot.Length).Trim('\/')
    foreach ($ex in $Exclude) {
        if ($relative -like "*$ex*" -or (Split-Path $dir -Leaf) -eq $ex) { return $false }
    }
    return $true
}

Write-Host "`n=== Clean-LabResources : directories to inspect ===" -ForegroundColor Cyan
$targets | ForEach-Object { Write-Host "  $_" }
Write-Host ''

$destroyed = @()
$skipped   = @()
$failed    = @()

foreach ($dir in $targets) {
    Push-Location $dir
    try {
        Write-Host "Inspecting $dir" -ForegroundColor Cyan

        $stateFile = Join-Path $dir 'terraform.tfstate'
        $stateContent = Get-Content $stateFile -Raw
        if ($stateContent -match '"resources"\s*:\s*\[\s*\]') {
            Write-Host "  State is empty; skipping" -ForegroundColor Green
            $skipped += $dir
            continue
        }

        $backendFile = Join-Path $dir 'backend.tf'
        $backendBak = "$backendFile.cleanup"
        if (Test-Path $backendBak) { Remove-Item $backendBak }
        $backendMoved = $false
        if (Test-Path $backendFile) {
            Move-Item $backendFile $backendBak
            $backendMoved = $true
        }

        if (-not $SkipInit) {
            Write-Host "  Initializing" -ForegroundColor Yellow
            $init = terraform init -backend=false -input=false -no-color 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "terraform init failed in $dir"
                $failed += $dir
                continue
            }
        }

        $stateList = terraform state list -no-color 2>&1
        $stateListExit = $LASTEXITCODE
        if ($stateListExit -ne 0) {
            Write-Warning "terraform state list failed in $dir (exit $stateListExit)"
            $failed += $dir
            continue
        }
        $resourceCount = ($stateList | ForEach-Object { "$_" } | Where-Object { $_.Trim() -ne '' }).Count

        if ($resourceCount -eq 0) {
            Write-Host "  No managed resources in state; skipping" -ForegroundColor Green
            $skipped += $dir
            continue
        }

        Write-Host "  Found $resourceCount resource(s)" -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess($dir, "terraform destroy -auto-approve")) {
            $stateRmTargets = $stateList | Where-Object { "$_" -match 'tag_association|tls_private_key|local_file' }
            if ($stateRmTargets) {
                Write-Host "  Removing stale/locked resources from state" -ForegroundColor Yellow
                $stateObj = Get-Content $stateFile -Raw | ConvertFrom-Json
                $badTypes = @('snowflake_tag_association','tls_private_key','local_file')
                $stateObj.resources = @($stateObj.resources | Where-Object { $_.type -notin $badTypes })
                $stateObj.serial = $stateObj.serial + 1
                $newJson = $stateObj | ConvertTo-Json -Depth 100 -Compress:$false
                Set-Content -Path $stateFile -Value $newJson -Encoding ascii -Force
                $stateList = terraform state list -no-color 2>&1
                $resourceCount = ($stateList | ForEach-Object { "$_" } | Where-Object { $_.Trim() -ne '' }).Count
            }
            terraform destroy -auto-approve -input=false -no-color 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning "terraform destroy failed in $dir"
                $failed += $dir
            } else {
                $destroyed += $dir
            }
        } else {
            $skipped += $dir
        }
    }
    finally {
        if ($backendMoved -and (Test-Path $backendBak)) { Move-Item $backendBak $backendFile }
        Pop-Location
    }
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "Destroyed : $($destroyed.Count)" -ForegroundColor Green
$destroyed | ForEach-Object { Write-Host "  OK  $_" }
if ($failed.Count -gt 0) {
    Write-Host "Failed    : $($failed.Count)" -ForegroundColor Red
    $failed | ForEach-Object { Write-Host "  FAIL $_" }
}
if ($skipped.Count -gt 0) {
    Write-Host "Skipped   : $($skipped.Count)" -ForegroundColor Yellow
    $skipped | ForEach-Object { Write-Host "  SKIP $_" }
}
