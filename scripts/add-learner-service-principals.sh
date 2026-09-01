#!/usr/bin/env bash
#
# Creates service principals for each learner with secret-based authentication.
#
# For each learner:
# - Creates an Azure AD app registration
# - Creates a service principal
# - Generates a client secret
# - Adds the SP to a security group "Data2AI-Learners"
# - Assigns RBAC roles on the subscription
#
# Service principals bypass MFA, so learners can use:
# az login --service-principal -u <appId> -p <secret> --tenant <tenantId>
#
# Usage:
#   ./scripts/add-learner-service-principals.sh
#   ./scripts/add-learner-service-principals.sh --role Contributor
#   ./scripts/add-learner-service-principals.sh --dry-run

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
secrets_dir="${project_root}/secrets"
secrets_file="${secrets_dir}/learner-sp-secrets.txt"

# ------------------------------------------------------------------
# Defaults
# ------------------------------------------------------------------

dry_run=false
role='Contributor'
group_name='Data2AI-Learners'

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)    dry_run=true; shift ;;
    --role)       role="$2"; shift 2 ;;
    --group-name) group_name="$2"; shift 2 ;;
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

subscription_id=$(az account show --query 'id' -o tsv 2>/dev/null)
tenant_id=$(az account show --query 'tenantId' -o tsv 2>/dev/null)

printf '[INFO] Subscription: %s (%s)\n' "$account" "$subscription_id" >&2
printf '[INFO] Tenant: %s\n' "$tenant_id" >&2
printf '[INFO] Role: %s\n' "$role" >&2
printf '[INFO] Group: %s\n' "$group_name" >&2

# ------------------------------------------------------------------
# Learner list
# ------------------------------------------------------------------

learners=()
for i in $(seq -w 1 10); do
  learners+=("apprenant${i}")
done

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

mode='PROVISION'
if $dry_run; then mode='DRY RUN (no changes)'; fi

printf '\n============================================================\n'
printf ' Learner Service Principals - %s\n' "$mode"
printf '============================================================\n'
printf ' Tenant      : %s\n' "$tenant_id"
printf ' Subscription: %s\n' "$subscription_id"
printf ' Role        : %s\n' "$role"
printf ' Group       : %s\n' "$group_name"
printf ' Learners    : %d\n' "${#learners[@]}"
printf '\n'

# ------------------------------------------------------------------
# Create security group
# ------------------------------------------------------------------

printf '== Security Group\n'

group_id=$(az ad group show --group "$group_name" --query 'id' -o tsv 2>/dev/null)
if [[ -n "$group_id" ]]; then
  printf '  [SKIP] Group already exists\n'
elif $dry_run; then
  printf '  [DRY] Would create group\n'
  group_id=''
else
  group_body='{"displayName":"'"$group_name"'","mailEnabled":false,"mailNickname":"'"$group_name"'","securityEnabled":true}'
  group_id=$(az rest --method post --url 'https://graph.microsoft.com/v1.0/groups' --body "$group_body" --headers 'Content-Type=application/json' --query 'id' -o tsv 2>/dev/null)
  if [[ -n "$group_id" ]]; then
    printf '  [PASS] Group created\n'
  else
    printf '  [FAIL] Group creation failed\n'
    exit 1
  fi
fi

# Assign role to group
if [[ -n "$group_id" ]] && ! $dry_run; then
  scope="/subscriptions/${subscription_id}"
  role_check=$(az role assignment list --assignee "$group_id" --role "$role" --scope "$scope" --query '[].id' -o tsv 2>/dev/null)
  if [[ -n "$role_check" ]]; then
    printf '  [SKIP] Role already assigned to group\n'
  else
    az role assignment create --assignee-object-id "$group_id" --assignee-principal-type Group --role "$role" --scope "$scope" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      printf '  [PASS] Role assigned to group\n'
    else
      printf '  [WARN] Group role assignment failed\n'
    fi
  fi
fi

printf '\n'

# ------------------------------------------------------------------
# Provision each SP
# ------------------------------------------------------------------

created=0
existing=0
failed=0
secret_lines=()

secret_lines+=("# Learner Service Principal Secrets")
secret_lines+=("# Generated: $(date '+%Y-%m-%d %H:%M:%S')")
secret_lines+=("# Tenant: $tenant_id")
secret_lines+=("# Subscription: $subscription_id")
secret_lines+=("# Format: learner|appId|secret|tenantId")
secret_lines+=("")

for learner in "${learners[@]}"; do
  app_name="sp-${learner}"
  printf -- '-- %s\n' "$learner"

  # Check if app exists
  app_id=$(az ad app list --display-name "$app_name" --query '[0].appId' -o tsv 2>/dev/null)
  if [[ -n "$app_id" ]]; then
    printf '   [SKIP] App already exists (appId: %s)\n' "$app_id"
    ((existing++))
  elif $dry_run; then
    printf '   [DRY] Would create app\n'
    ((created++))
    continue
  else
    app_id=$(az ad app create --display-name "$app_name" --query 'appId' -o tsv 2>/dev/null)
    if [[ -n "$app_id" ]]; then
      printf '   [PASS] App created (appId: %s)\n' "$app_id"
      ((created++))
    else
      printf '   [FAIL] App creation failed\n'
      ((failed++))
      continue
    fi
  fi

  # Create SP if not exists
  sp_check=$(az ad sp list --filter "appId eq '$app_id'" --query '[0].id' -o tsv 2>/dev/null)
  if [[ -z "$sp_check" ]] && ! $dry_run; then
    az ad sp create --id "$app_id" >/dev/null 2>&1
    if [[ $? -eq 0 ]]; then
      printf '   [PASS] Service principal created\n'
    else
      printf '   [WARN] SP creation failed\n'
    fi
  elif [[ -n "$sp_check" ]]; then
    printf '   [SKIP] SP already exists\n'
  fi

  # Generate client secret
  if ! $dry_run; then
    secret_raw=$(az ad app credential reset --id "$app_id" --append 2>/dev/null)
    secret_value=$(echo "$secret_raw" | python3 -c "import sys,json; print(json.load(sys.stdin)['password'])" 2>/dev/null)
    if [[ -n "$secret_value" ]]; then
      printf '   [PASS] Client secret generated\n'
      secret_lines+=("${learner}|${app_id}|${secret_value}|${tenant_id}")
    else
      printf '   [WARN] Secret generation failed\n'
    fi
  fi

  # Add to group
  if [[ -n "$group_id" ]] && ! $dry_run; then
    sp_id=$(az ad sp list --filter "appId eq '$app_id'" --query '[0].id' -o tsv 2>/dev/null)
    if [[ -n "$sp_id" ]]; then
      member_body='{"@odata.id":"https://graph.microsoft.com/v1.0/directoryObjects/'"$sp_id"'"}'
      az rest --method post --url "https://graph.microsoft.com/v1.0/groups/${group_id}/members/\$ref" --body "$member_body" --headers 'Content-Type=application/json' >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        printf '   [PASS] Added to group\n'
      else
        printf '   [SKIP] Already in group or failed\n'
      fi
    fi
  fi

  # Assign role directly to SP
  if ! $dry_run; then
    scope="/subscriptions/${subscription_id}"
    role_check=$(az role assignment list --assignee "$app_id" --role "$role" --scope "$scope" --query '[].id' -o tsv 2>/dev/null)
    if [[ -n "$role_check" ]]; then
      printf '   [SKIP] Role already assigned to SP\n'
    else
      az role assignment create --assignee "$app_id" --role "$role" --scope "$scope" >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        printf '   [PASS] Role assigned to SP\n'
      else
        printf '   [WARN] SP role assignment failed\n'
      fi
    fi
  fi

  printf '\n'
done

# ------------------------------------------------------------------
# Save secrets
# ------------------------------------------------------------------

if ! $dry_run && [[ ${#secret_lines[@]} -gt 6 ]]; then
  mkdir -p "$secrets_dir"
  printf '%s\n' "${secret_lines[@]}" > "$secrets_file"
  printf 'Secrets saved to: %s\n\n' "$secrets_file" >&2
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

printf '============================================================\n'
printf ' Summary\n'
printf '============================================================\n\n'
printf '  Created      : %d\n' "$created"
printf '  Already exist: %d\n' "$existing"
printf '  Failed       : %d\n\n' "$failed"

if [[ $failed -gt 0 ]]; then
  printf 'Status: PARTIAL\n'
  exit 1
else
  printf 'Status: DONE\n\n'
  printf 'Learners can now login with:\n'
  printf '  az login --service-principal -u <appId> -p <secret> --tenant <tenantId>\n\n'
  printf 'Secrets file: %s (gitignored)\n\n' "$secrets_file"
  printf 'Or set environment variables:\n'
  printf '  export ARM_CLIENT_ID="<appId>"\n'
  printf '  export ARM_CLIENT_SECRET="<secret>"\n'
  printf '  export ARM_TENANT_ID="<tenantId>"\n'
  printf '  export ARM_SUBSCRIPTION_ID="<subscriptionId>"\n'
  exit 0
fi
