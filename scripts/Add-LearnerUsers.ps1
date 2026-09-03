#requires -version 5.1
<#
.SYNOPSIS
    Creates learner users in Azure AD (Entra ID) and Azure DevOps.

.DESCRIPTION
    Reads a users file (format: username: password) and creates each user
    in Azure AD with the tenant's default verified domain.
    Assigns a subscription role (Reader by default).
    Optionally adds users to an Azure DevOps organization.

    The users file must be in secrets/ (gitignored). Passwords are never
    displayed or logged.

.PARAMETER UsersFile
    Path to the users file. Default: secrets/users_azures.txt
    Format: one user per line as "username: password"

.PARAMETER Domain
    Azure AD verified domain for UPNs. If omitted, the tenant default is used.

.PARAMETER Role
    Azure RBAC role to assign. Default: Reader.
    Use Contributor for full access.

.PARAMETER SubscriptionId
    Subscription to assign the role on. If omitted, current subscription is used.

.PARAMETER DevOpsOrg
    Azure DevOps organization URL (e.g. https://dev.azure.com/myorg).
    If set, users are also added to DevOps.

.PARAMETER DevOpsProject
    Azure DevOps project name. If set with DevOpsOrg, users are added to the project.

.PARAMETER DryRun
    Show what would be done without making any changes.

.EXAMPLE
    .\scripts\Add-LearnerUsers.ps1
    .\scripts\Add-LearnerUsers.ps1 -Role Contributor
    .\scripts\Add-LearnerUsers.ps1 -DryRun
    .\scripts\Add-LearnerUsers.ps1 -DevOpsOrg https://dev.azure.com/myorg -DevOpsProject DataPlatform
#>

[CmdletBinding()]
param(
    [string]$UsersFile,
    [string]$Domain,
    [string]$Role = 'Reader',
    [string]$SubscriptionId,
    [string]$DevOpsOrg,
    [string]$DevOpsProject,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
# DO NOT set PYTHONUTF8=1: it makes Python decode subprocess output (e.g. icacls)
# as UTF-8, which crashes on French Windows where icacls emits cp1252 bytes.

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir

# ------------------------------------------------------------------
# Resolve users file
# ------------------------------------------------------------------

if (-not $UsersFile) {
    $UsersFile = Join-Path $projectRoot 'secrets\users_azures.txt'
}

if (-not (Test-Path $UsersFile)) {
    Write-Host "[FAIL] Users file not found: $UsersFile" -ForegroundColor Red
    Write-Host "       Expected format: one user per line as 'username: password'" -ForegroundColor DarkGray
    exit 1
}

# ------------------------------------------------------------------
# Check Azure CLI
# ------------------------------------------------------------------

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    Write-Host '[FAIL] Azure CLI not installed' -ForegroundColor Red
    exit 1
}

# Verify login
$account = & az account show --query 'name' -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or -not $account) {
    Write-Host '[FAIL] Not logged in to Azure. Run: az login' -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Azure subscription: $account" -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Resolve domain
# ------------------------------------------------------------------

if (-not $Domain) {
    Write-Host '[INFO] Detecting Azure AD default domain...' -ForegroundColor DarkGray
    $Domain = & az rest --method get --url 'https://graph.microsoft.com/v1.0/organization' --query 'value[0].verifiedDomains[?isDefault].name' -o tsv 2>&1
    if ($LASTEXITCODE -ne 0 -or -not $Domain) {
        Write-Host '[FAIL] Could not detect Azure AD default domain' -ForegroundColor Red
        Write-Host '       Specify -Domain explicitly, e.g. -Domain yourtenant.onmicrosoft.com' -ForegroundColor DarkGray
        exit 1
    }
}

Write-Host "[INFO] Azure AD domain: $Domain" -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Resolve subscription
# ------------------------------------------------------------------

if (-not $SubscriptionId) {
    $SubscriptionId = & az account show --query 'id' -o tsv 2>&1
}

Write-Host "[INFO] Subscription ID: $SubscriptionId" -ForegroundColor DarkGray
Write-Host "[INFO] Role: $Role" -ForegroundColor DarkGray

# ------------------------------------------------------------------
# Parse users file
# ------------------------------------------------------------------

$users = @()
Get-Content $UsersFile | ForEach-Object {
    $line = $_.Trim()
    if ($line -and $line -notmatch '^#') {
        $sep = $line.IndexOf(':')
        if ($sep -gt 0) {
            $username = $line.Substring(0, $sep).Trim()
            $password = $line.Substring($sep + 1).Trim()
            if ($username -and $password) {
                $users += [PSCustomObject]@{
                    Username = $username
                    Password = $password
                    UPN      = "$username@$Domain"
                }
            }
        }
    }
}

if ($users.Count -eq 0) {
    Write-Host '[FAIL] No valid users found in file' -ForegroundColor Red
    Write-Host "       Format: username: password (one per line)" -ForegroundColor DarkGray
    exit 1
}

Write-Host "[INFO] Found $($users.Count) users to provision" -ForegroundColor DarkGray
Write-Host ''

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

$mode = if ($DryRun) { 'DRY RUN (no changes)' } else { 'PROVISION' }

Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Learner User Provisioning - $mode" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host " Domain     : $Domain"
Write-Host " Role       : $Role"
Write-Host " Subscription: $SubscriptionId"
if ($DevOpsOrg) {
    Write-Host " DevOps org : $DevOpsOrg"
    if ($DevOpsProject) { Write-Host " DevOps proj: $DevOpsProject" }
}
Write-Host " Users file : $UsersFile"
Write-Host " Users count: $($users.Count)"
Write-Host ''

# ------------------------------------------------------------------
# Provision each user
# ------------------------------------------------------------------

$created = 0
$existing = 0
$failed = 0
$roleAssigned = 0

foreach ($u in $users) {
    Write-Host "-- $($u.Username) ($($u.UPN))" -ForegroundColor Cyan

    # Check if user already exists
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $existingUser = & az ad user show --id $u.UPN --query 'userPrincipalName' -o tsv 2>&1
    $userExists = ($LASTEXITCODE -eq 0 -and $existingUser)
    $ErrorActionPreference = $prevEAP

    if ($userExists) {
        Write-Host "   [SKIP] User already exists in Azure AD" -ForegroundColor Yellow
        $existing++
    } elseif ($DryRun) {
        Write-Host "   [DRY] Would create user in Azure AD" -ForegroundColor DarkGray
        $created++
    } else {
        # Create user in Azure AD
        $displayName = $u.Username
        $mailNickname = $u.Username
        $securePassword = $u.Password

        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $createResult = & az ad user create `
            --display-name $displayName `
            --user-principal-name $u.UPN `
            --mail-nickname $mailNickname `
            --password $securePassword `
            --query 'userPrincipalName' -o tsv 2>&1
        $createExit = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP

        if ($createExit -eq 0 -and $createResult) {
            Write-Host "   [PASS] Created in Azure AD" -ForegroundColor Green
            $created++
        } else {
            Write-Host "   [FAIL] Azure AD creation failed" -ForegroundColor Red
            Write-Host "         $createResult" -ForegroundColor DarkGray
            $failed++
            continue
        }
    }

    # Assign RBAC role on subscription
    $scope = "/subscriptions/$SubscriptionId"
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $roleCheck = & az role assignment list --assignee $u.UPN --role $Role --scope $scope --query '[].id' -o tsv 2>&1

    if ($roleCheck) {
        Write-Host "   [SKIP] Role '$Role' already assigned" -ForegroundColor Yellow
    } elseif ($DryRun) {
        Write-Host "   [DRY] Would assign role '$Role' on subscription" -ForegroundColor DarkGray
    } else {
        $roleResult = & az role assignment create --assignee $u.UPN --role $Role --scope $scope --query 'name' -o tsv 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "   [PASS] Role '$Role' assigned on subscription" -ForegroundColor Green
            $roleAssigned++
        } else {
            Write-Host "   [WARN] Role assignment failed: $roleResult" -ForegroundColor Yellow
        }
    }
    $ErrorActionPreference = $prevEAP

    # Add to Azure DevOps (if configured)
    if ($DevOpsOrg) {
        if ($DryRun) {
            Write-Host "   [DRY] Would add to Azure DevOps" -ForegroundColor DarkGray
        } else {
            # Use az devops user add (uses az login token, no PAT needed)
            $prevEAP = $ErrorActionPreference
            $ErrorActionPreference = 'Continue'
            $adoResult = & az devops user add --org $DevOpsOrg --email-id $u.UPN --license-type express --query 'user.principalName' -o tsv 2>&1
            $adoExit = $LASTEXITCODE
            $ErrorActionPreference = $prevEAP

            if ($adoExit -eq 0 -and $adoResult) {
                Write-Host "   [PASS] Added to Azure DevOps" -ForegroundColor Green
            } elseif ($adoResult -match 'already') {
                Write-Host "   [SKIP] Already in Azure DevOps" -ForegroundColor Yellow
            } else {
                Write-Host "   [WARN] DevOps add failed: $adoResult" -ForegroundColor Yellow
            }
        }
    }

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
Write-Host "  Roles assigned: $roleAssigned"
Write-Host ''

if ($failed -gt 0) {
    Write-Host 'Status: PARTIAL - some users failed' -ForegroundColor Yellow
    exit 1
} else {
    Write-Host 'Status: DONE' -ForegroundColor Green
    Write-Host ''
    Write-Host 'Learners can now login with:' -ForegroundColor DarkGray
    Write-Host "  az login -u apprenant01@$Domain" -ForegroundColor DarkGray
    Write-Host ''
    Write-Host 'Passwords are in secrets/users_azures.txt (gitignored)' -ForegroundColor DarkGray
    exit 0
}
