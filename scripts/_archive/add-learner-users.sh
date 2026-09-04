#!/usr/bin/env bash
#
# Creates learner users in Azure AD (Entra ID) and Azure DevOps.
#
# Reads a users file (format: username: password) and creates each user
# in Azure AD with the tenant's default verified domain.
# Assigns a subscription role (Reader by default).
# Optionally adds users to an Azure DevOps organization.
#
# Usage:
#   ./scripts/add-learner-users.sh
#   ./scripts/add-learner-users.sh --role Contributor
#   ./scripts/add-learner-users.sh --dry-run
#   ./scripts/add-learner-users.sh --devops-org https://dev.azure.com/myorg --devops-project DataPlatform

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------

users_file="${project_root}/secrets/users_azures.txt"
domain=''
role='Reader'
subscription_id=''
devops_org=''
devops_project=''
dry_run=false

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --users-file)      users_file="$2"; shift 2 ;;
    --domain)          domain="$2"; shift 2 ;;
    --role)            role="$2"; shift 2 ;;
    --subscription-id) subscription_id="$2"; shift 2 ;;
    --devops-org)      devops_org="$2"; shift 2 ;;
    --devops-project)  devops_project="$2"; shift 2 ;;
    --dry-run)         dry_run=true; shift ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------
# Check Azure CLI
# ------------------------------------------------------------------

if ! command -v az >/dev/null 2>&1; then
  printf '[FAIL] Azure CLI not installed\n' >&2
  exit 1
fi

account=$(az account show --query 'name' -o tsv 2>/dev/null)
if [[ $? -ne 0 ]] || [[ -z "$account" ]]; then
  printf '[FAIL] Not logged in to Azure. Run: az login\n' >&2
  exit 1
fi

printf '[INFO] Azure subscription: %s\n' "$account" >&2

# ------------------------------------------------------------------
# Resolve domain
# ------------------------------------------------------------------

if [[ -z "$domain" ]]; then
  printf '[INFO] Detecting Azure AD default domain...\n' >&2
  domain=$(az rest --method get --url 'https://graph.microsoft.com/v1.0/organization' --query 'value[0].verifiedDomains[?isDefault].name' -o tsv 2>/dev/null)
  if [[ $? -ne 0 ]] || [[ -z "$domain" ]]; then
    printf '[FAIL] Could not detect Azure AD default domain\n' >&2
    printf '       Specify --domain explicitly\n' >&2
    exit 1
  fi
fi

printf '[INFO] Azure AD domain: %s\n' "$domain" >&2

# ------------------------------------------------------------------
# Resolve subscription
# ------------------------------------------------------------------

if [[ -z "$subscription_id" ]]; then
  subscription_id=$(az account show --query 'id' -o tsv 2>/dev/null)
fi

printf '[INFO] Subscription ID: %s\n' "$subscription_id" >&2
printf '[INFO] Role: %s\n' "$role" >&2

# ------------------------------------------------------------------
# Check users file
# ------------------------------------------------------------------

if [[ ! -f "$users_file" ]]; then
  printf '[FAIL] Users file not found: %s\n' "$users_file" >&2
  exit 1
fi

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

mode='PROVISION'
if $dry_run; then mode='DRY RUN (no changes)'; fi

printf '\n============================================================\n'
printf ' Learner User Provisioning - %s\n' "$mode"
printf '============================================================\n'
printf ' Domain      : %s\n' "$domain"
printf ' Role        : %s\n' "$role"
printf ' Subscription: %s\n' "$subscription_id"
if [[ -n "$devops_org" ]]; then
  printf ' DevOps org  : %s\n' "$devops_org"
  if [[ -n "$devops_project" ]]; then printf ' DevOps proj : %s\n' "$devops_project"; fi
fi
printf ' Users file  : %s\n' "$users_file"
printf '\n'

# ------------------------------------------------------------------
# Provision each user
# ------------------------------------------------------------------

created=0
existing=0
failed=0
role_assigned=0

scope="/subscriptions/${subscription_id}"

while IFS=': ' read -r username password || [[ -n "$username" ]]; do
  username="${username//[[:space:]]/}"
  password="${password//[[:space:]]/}"

  [[ -z "$username" ]] && continue
  [[ "$username" =~ ^# ]] && continue
  [[ -z "$password" ]] && continue

  upn="${username}@${domain}"

  printf -- '-- %s (%s)\n' "$username" "$upn"

  # Check if user already exists
  existing_check=$(az ad user show --id "$upn" --query 'userPrincipalName' -o tsv 2>/dev/null)
  if [[ $? -eq 0 ]] && [[ -n "$existing_check" ]]; then
    printf '   [SKIP] User already exists in Azure AD\n'
    ((existing++))
  elif $dry_run; then
    printf '   [DRY] Would create user in Azure AD\n'
    ((created++))
  else
    create_result=$(az ad user create \
      --display-name "$username" \
      --user-principal-name "$upn" \
      --mail-nickname "$username" \
      --password "$password" \
      --query 'userPrincipalName' -o tsv 2>&1)
    if [[ $? -eq 0 ]] && [[ -n "$create_result" ]]; then
      printf '   [PASS] Created in Azure AD\n'
      ((created++))
    else
      printf '   [FAIL] Azure AD creation failed\n'
      printf '          %s\n' "$create_result" >&2
      ((failed++))
      printf '\n'
      continue
    fi
  fi

  # Assign RBAC role
  role_check=$(az role assignment list --assignee "$upn" --role "$role" --scope "$scope" --query '[].id' -o tsv 2>/dev/null)
  if [[ -n "$role_check" ]]; then
    printf '   [SKIP] Role already assigned\n'
  elif $dry_run; then
    printf '   [DRY] Would assign role %s\n' "$role"
  else
    role_result=$(az role assignment create --assignee "$upn" --role "$role" --scope "$scope" --query 'name' -o tsv 2>&1)
    if [[ $? -eq 0 ]]; then
      printf '   [PASS] Role %s assigned\n' "$role"
      ((role_assigned++))
    else
      printf '   [WARN] Role assignment failed\n'
    fi
  fi

  # Add to Azure DevOps
  if [[ -n "$devops_org" ]]; then
    if $dry_run; then
      printf '   [DRY] Would add to Azure DevOps\n'
    else
      ado_result=$(az devops user add --org "$devops_org" --email-id "$upn" --license-type express --query 'user.principalName' -o tsv 2>&1)
      ado_exit=$?
      if [[ $ado_exit -eq 0 ]] && [[ -n "$ado_result" ]]; then
        printf '   [PASS] Added to Azure DevOps\n'
      elif [[ "$ado_result" == *already* ]]; then
        printf '   [SKIP] Already in Azure DevOps\n'
      else
        printf '   [WARN] DevOps add failed\n'
      fi
    fi
  fi

  printf '\n'

done < "$users_file"

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

printf '============================================================\n'
printf ' Summary\n'
printf '============================================================\n\n'
printf '  Created       : %d\n' "$created"
printf '  Already exist : %d\n' "$existing"
printf '  Failed        : %d\n' "$failed"
printf '  Roles assigned: %d\n\n' "$role_assigned"

if [[ $failed -gt 0 ]]; then
  printf 'Status: PARTIAL - some users failed\n'
  exit 1
else
  printf 'Status: DONE\n\n'
  printf 'Learners can now login with:\n'
  printf '  az login -u apprenant01@%s\n\n' "$domain"
  printf 'Passwords are in secrets/users_azures.txt (gitignored)\n'
  exit 0
fi
