#!/usr/bin/env bash
#
# Learner login script - authenticates to Azure using the shared service principal.
#
# Reads the shared SP credentials from secrets/shared-sp.txt and logs in.
# Sets ARM_* environment variables for Terraform.
# Sets LEARNER_PREFIX for resource isolation.
#
# No MFA required - service principals bypass MFA enforcement.
#
# Usage:
#   ./scripts/learner-login.sh APP01
#   ./scripts/learner-login.sh APP03 --secrets-file ./secrets/shared-sp.txt

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
secrets_file="${project_root}/secrets/shared-sp.txt"
learner_prefix=''

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secrets-file) secrets_file="$2"; shift 2 ;;
    -h|--help) sed -n '2,10p' "$0"; exit 0 ;;
    *) learner_prefix="$1"; shift ;;
  esac
done

if [[ -z "$learner_prefix" ]]; then
  printf 'Usage: %s <LearnerPrefix> [--secrets-file <path>]\n' "$0" >&2
  printf '  LearnerPrefix: APP01 to APP10\n' >&2
  exit 2
fi

if [[ ! "$learner_prefix" =~ ^APP[0-9]{2}$ ]]; then
  printf '[FAIL] Invalid prefix: %s (expected APP01-APP10)\n' "$learner_prefix" >&2
  exit 2
fi

# ------------------------------------------------------------------
# Check secrets file
# ------------------------------------------------------------------

if [[ ! -f "$secrets_file" ]]; then
  printf '[FAIL] Shared SP file not found: %s\n' "$secrets_file" >&2
  printf '       Ask your instructor for the shared-sp.txt file\n' >&2
  exit 1
fi

# ------------------------------------------------------------------
# Parse shared SP file
# ------------------------------------------------------------------

declare -A creds
while IFS='=' read -r key val || [[ -n "$key" ]]; do
  key="${key//[[:space:]]/}"
  val="${val//[[:space:]]/}"
  [[ "$key" =~ ^# ]] && continue
  [[ -z "$key" ]] && continue
  creds["$key"]="$val"
done < "$secrets_file"

for k in ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID; do
  if [[ -z "${creds[$k]:-}" ]]; then
    printf '[FAIL] Missing %s in %s\n' "$k" "$secrets_file" >&2
    exit 1
  fi
done

# ------------------------------------------------------------------
# Login
# ------------------------------------------------------------------

printf '============================================================\n'
printf ' Learner Login: %s\n' "$learner_prefix"
printf '============================================================\n\n'

printf '[INFO] Logging in with shared service principal...\n'

login_result=$(az login --service-principal \
  -u "${creds[ARM_CLIENT_ID]}" \
  -p "${creds[ARM_CLIENT_SECRET]}" \
  --tenant "${creds[ARM_TENANT_ID]}" 2>&1)
if [[ $? -ne 0 ]]; then
  printf '[FAIL] Login failed\n' >&2
  printf '       %s\n' "$login_result" >&2
  exit 1
fi

az account set --subscription "${creds[ARM_SUBSCRIPTION_ID]}" >/dev/null 2>&1

sub_name=$(az account show --query 'name' -o tsv 2>/dev/null)
printf '[PASS] Logged in to Azure\n'
printf '       Subscription: %s (%s)\n' "$sub_name" "${creds[ARM_SUBSCRIPTION_ID]}"
printf '       Tenant: %s\n' "${creds[ARM_TENANT_ID]}"
printf '       Learner prefix: %s\n\n' "$learner_prefix"

# ------------------------------------------------------------------
# Set ARM environment variables
# ------------------------------------------------------------------

export ARM_CLIENT_ID="${creds[ARM_CLIENT_ID]}"
export ARM_CLIENT_SECRET="${creds[ARM_CLIENT_SECRET]}"
export ARM_TENANT_ID="${creds[ARM_TENANT_ID]}"
export ARM_SUBSCRIPTION_ID="${creds[ARM_SUBSCRIPTION_ID]}"
export LEARNER_PREFIX="$learner_prefix"

printf '[PASS] Environment variables set:\n'
printf '       ARM_CLIENT_ID\n'
printf '       ARM_CLIENT_SECRET (hidden)\n'
printf '       ARM_TENANT_ID\n'
printf '       ARM_SUBSCRIPTION_ID\n'
printf '       LEARNER_PREFIX = %s\n\n' "$learner_prefix"

printf '============================================================\n'
printf ' Ready for labs\n'
printf '============================================================\n\n'
printf 'Next steps:\n'
printf '  ./scripts/test-lab-connectivity.sh --skip-devops\n\n'
