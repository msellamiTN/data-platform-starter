#requires -version 5.1
<#
.SYNOPSIS
    Creates service principals for each learner with secret-based authentication.

.DESCRIPTION
    For each learner:
    - Creates an Azure AD app registration
    - Creates a service principal
    - Generates a client secret
    - Adds the SP to a security group "Data2AI-Learners"
    - Assigns RBAC roles on the subscription

    Service principals bypass MFA, so learners can use:
    az login --service-principal -u <appId> -p <secret> --tenant <tenantId>

    No user passwords needed. Secrets are saved to secrets/learner-sp-secrets.txt (gitignored).

.PARAMETER DryRun
    Show what would be done without making changes.

.PARAMETER Role
    RBAC role for the subscription. Default: Contributor.

.EXAMPLE
    .\scripts\Add-LearnerServicePrincipals.ps1
    .\scripts\Add-LearnerServicePrincipals.ps1 -Role Contributor
    .\scripts\Add-LearnerServicePrincipals.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$Role = 'Contributor',
    [string]$GroupName = 'Data2AI-Learners'
)

$ErrorActionPreference = 'Stop'
$env:PYTHONUTF8 = '1'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$secretsDir = Join-Path $projectRoot 'secrets'
$secretsFile = Join-Path $secretsDir 'learner-sp-secrets.txt'

# ------------------------------------------------------------------
# Check Azure CLI
# ------------------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host '[FAIL] Azure CLI not installed' -ForegroundColor Red
    exit 1
}

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$account = & az account show --query 'name' -o tsv 2>&1
$ErrorActionPreference = $prevEAP

if ($LASTEXITCODE -ne 0 -or -not $account) {
    Write-Host '[FAIL] Not logged in to Azure. Run: az login' -ForegroundColor Red
    exit 1
}

$subscriptionId = & az account show --query 'id' -o tsv 2>&1
$tenantId = & az account show --query 'tenantId' -o tsv 2>&1

Write-Host "[INFO] Subscription: $account ($subscriptionId)" -ForegroundColor DarkGray
Write-Host "[INFO] Tenant: $tenantId" -ForegroundColor DarkGray
Write-Host "[INFO] Role: $Role" -ForegroundColor DarkGray
Write-Host "[INFO] Group: $GroupName" -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Learner list
# ------------------------------------------------------------------

$learners = 1..10 | ForEach-Object {
    $padded = '{0:D2}' -f $_
    [PSCustomObject]@{
        Name  = "apprenant$padded"
        AppName = "sp-apprenant$padded"
    }
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

$mode = if ($DryRun) { 'DRY RUN (no changes)' } else { 'PROVISION' }

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Learner Service Principals - $mode" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Tenant     : $tenantId"
Write-Host " Subscription: $subscriptionId"
Write-Host " Role       : $Role"
Write-Host " Group      : $GroupName"
Write-Host " Learners   : $($learners.Count)"
Write-Host ''

# ------------------------------------------------------------------
# Create security group
# ------------------------------------------------------------------

Write-Host '== Security Group' -ForegroundColor Cyan

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$groupCheck = & az ad group show --group $GroupName --query 'id' -o tsv 2>&1
$ErrorActionPreference = $prevEAP

if ($groupCheck) {
    Write-Host "  [SKIP] Group '$GroupName' already exists" -ForegroundColor Yellow
    $groupId = $groupCheck
} elseif ($DryRun) {
    Write-Host "  [DRY] Would create group '$GroupName'" -ForegroundColor DarkGray
    $groupId = $null
} else {
    $groupBody = @{ displayName = $GroupName; mailEnabled = $false; mailNickname = $GroupName; securityEnabled = $true } | ConvertTo-Json -Compress
    $groupBodyFile = [System.IO.Path]::GetTempFileName()
    Set-Content $groupBodyFile -Value $groupBody -Encoding utf8
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $groupResult = & az rest --method post --url 'https://graph.microsoft.com/v1.0/groups' --body "@$groupBodyFile" --headers 'Content-Type=application/json' --query 'id' -o tsv 2>&1
    $ErrorActionPreference = $prevEAP
    Remove-Item $groupBodyFile -Force
    if ($LASTEXITCODE -eq 0 -and $groupResult) {
        Write-Host "  [PASS] Group '$GroupName' created" -ForegroundColor Green
        $groupId = $groupResult
    } else {
        Write-Host "  [FAIL] Group creation failed: $groupResult" -ForegroundColor Red
        exit 1
    }
}

# ------------------------------------------------------------------
# Assign RBAC role to the group
# ------------------------------------------------------------------

if ($groupId -and -not $DryRun) {
    $scope = "/subscriptions/$subscriptionId"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $roleCheck = & az role assignment list --assignee $groupId --role $Role --scope $scope --query '[].id' -o tsv 2>&1
    if ($roleCheck) {
        Write-Host "  [SKIP] Role '$Role' already assigned to group" -ForegroundColor Yellow
    } else {
        $roleResult = & az role assignment create --assignee-object-id $groupId --assignee-principal-type Group --role $Role --scope $scope --query 'name' -o tsv 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  [PASS] Role '$Role' assigned to group" -ForegroundColor Green
        } else {
            Write-Host "  [WARN] Role assignment failed: $roleResult" -ForegroundColor Yellow
        }
    }
    $ErrorActionPreference = $prevEAP
}

Write-Host ''

# ------------------------------------------------------------------
# Provision each service principal
# ------------------------------------------------------------------

$created = 0
$existing = 0
$failed = 0
$secretLines = @()

# Write header to secrets file
$secretLines += "# Learner Service Principal Secrets"
$secretLines += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
$secretLines += "# Tenant: $tenantId"
$secretLines += "# Subscription: $subscriptionId"
$secretLines += "# Format: learner|appId|secret|tenantId"
$secretLines += ""

foreach ($l in $learners) {
    Write-Host "-- $($l.Name)" -ForegroundColor Cyan

    # Check if app already exists
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $appCheck = & az ad app list --display-name $l.AppName --query '[0].appId' -o tsv 2>&1
    $ErrorActionPreference = $prevEAP

    if ($appCheck) {
        Write-Host "   [SKIP] App '$($l.AppName)' already exists (appId: $appCheck)" -ForegroundColor Yellow
        $appId = $appCheck
        $existing++
    } elseif ($DryRun) {
        Write-Host "   [DRY] Would create app '$($l.AppName)'" -ForegroundColor DarkGray
        $created++
        continue
    } else {
        # Create app registration
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $appId = & az ad app create --display-name $l.AppName --query 'appId' -o tsv 2>&1
        $appExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($appExit -eq 0 -and $appId) {
            Write-Host "   [PASS] App created (appId: $appId)" -ForegroundColor Green
            $created++
        } else {
            Write-Host "   [FAIL] App creation failed" -ForegroundColor Red
            $failed++
            continue
        }
    }

    # Create service principal if not exists
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $spCheck = & az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv 2>&1
    $ErrorActionPreference = $prevEAP

    if (-not $spCheck -and -not $DryRun) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $spResult = & az ad sp create --id $appId --query 'id' -o tsv 2>&1
        $ErrorActionPreference = $prevEAP
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [PASS] Service principal created" -ForegroundColor Green
        } else {
            Write-Host "   [WARN] SP creation failed: $spResult" -ForegroundColor Yellow
        }
    } elseif ($spCheck) {
        Write-Host "   [SKIP] Service principal already exists" -ForegroundColor DarkGray
    }

    # Generate client secret
    if (-not $DryRun) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $secretRaw = & az ad app credential reset --id $appId --append 2>&1
        $secretExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        # Parse JSON from output (warning text may be mixed in)
        $secretValue = $null
        if ($secretExit -eq 0 -and $secretRaw) {
            $jsonStart = ($secretRaw -join "`n").IndexOf('{')
            if ($jsonStart -ge 0) {
                $jsonStr = ($secretRaw -join "`n").Substring($jsonStart)
                try {
                    $secretObj = $jsonStr | ConvertFrom-Json
                    $secretValue = $secretObj.password
                } catch {
                    # Fallback: try line-by-line
                }
            }
        }

        if ($secretValue) {
            Write-Host "   [PASS] Client secret generated" -ForegroundColor Green
            $secretLines += "$($l.Name)|$appId|$secretValue|$tenantId"
        } else {
            Write-Host "   [WARN] Secret generation failed" -ForegroundColor Yellow
        }
    }

    # Add SP to security group
    if ($groupId -and -not $DryRun) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $spId = & az ad sp list --filter "appId eq '$appId'" --query '[0].id' -o tsv 2>&1
        $ErrorActionPreference = $prevEAP

        if ($spId) {
            $groupMemberObj = [PSCustomObject]@{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$spId" }
            $groupMemberBody = $groupMemberObj | ConvertTo-Json -Compress
            $groupMemberFile = [System.IO.Path]::GetTempFileName()
            Set-Content $groupMemberFile -Value $groupMemberBody -Encoding utf8

            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $addResult = & az rest --method post --url "https://graph.microsoft.com/v1.0/groups/$groupId/members/`$ref" --body "@$groupMemberFile" --headers 'Content-Type=application/json' 2>&1
            $addExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP
            Remove-Item $groupMemberFile -Force

            if ($addExit -eq 0) {
                Write-Host "   [PASS] Added to group '$GroupName'" -ForegroundColor Green
            } else {
                # May already be a member
                Write-Host "   [SKIP] Already in group or add failed" -ForegroundColor DarkGray
            }
        }
    }

    # Assign RBAC role directly to the SP (needed for az login to see subscription)
    if (-not $DryRun) {
        $scope = "/subscriptions/$subscriptionId"
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $roleCheck = & az role assignment list --assignee $appId --role $Role --scope $scope --query '[].id' -o tsv 2>&1
        if ($roleCheck) {
            Write-Host "   [SKIP] Role '$Role' already assigned to SP" -ForegroundColor DarkGray
        } else {
            $roleResult = & az role assignment create --assignee $appId --role $Role --scope $scope --query 'name' -o tsv 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Host "   [PASS] Role '$Role' assigned to SP" -ForegroundColor Green
            } else {
                Write-Host "   [WARN] SP role assignment failed" -ForegroundColor Yellow
            }
        }
        $ErrorActionPreference = $prevEAP
    }

    Write-Host ''
}

# ------------------------------------------------------------------
# Save secrets file
# ------------------------------------------------------------------

if (-not $DryRun -and $secretLines.Count -gt 6) {
    if (-not (Test-Path $secretsDir)) {
        New-Item -ItemType Directory -Path $secretsDir -Force | Out-Null
    }
    $secretLines | Set-Content -Path $secretsFile -Encoding utf8
    Write-Host "Secrets saved to: $secretsFile" -ForegroundColor DarkGray
    Write-Host ''
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ''
Write-Host "  Created      : $created"
Write-Host "  Already exist: $existing"
Write-Host "  Failed       : $failed"
Write-Host ''

if ($failed -gt 0) {
    Write-Host 'Status: PARTIAL' -ForegroundColor Yellow
    exit 1
} else {
    Write-Host 'Status: DONE' -ForegroundColor Green
    if (-not $DryRun) {
        Write-Host ''
        Write-Host 'Learners can now login with:' -ForegroundColor DarkGray
        Write-Host '  az login --service-principal -u <appId> -p <secret> --tenant <tenantId>' -ForegroundColor DarkGray
        Write-Host ''
        Write-Host "Secrets file: $secretsFile (gitignored)" -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'Or set environment variables:' -ForegroundColor DarkGray
        Write-Host '  $env:ARM_CLIENT_ID = "<appId>"' -ForegroundColor DarkGray
        Write-Host '  $env:ARM_CLIENT_SECRET = "<secret>"' -ForegroundColor DarkGray
        Write-Host '  $env:ARM_TENANT_ID = "<tenantId>"' -ForegroundColor DarkGray
        Write-Host '  $env:ARM_SUBSCRIPTION_ID = "<subscriptionId>"' -ForegroundColor DarkGray
    }
    exit 0
}
