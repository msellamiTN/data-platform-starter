#!/usr/bin/env bash
#
# Learner login script - authenticates to Azure using the shared service principal.
#
# Reads project settings from .env and the shared SP credentials from
# secrets/shared-sp.txt. Sets ARM_* variables and LEARNER_PREFIX.
#
# Source this script so exports persist in the current shell:
#   source ./scripts/learner-login.sh APP01
#   source ./scripts/learner-login.sh APP03 --secrets-file ./secrets/shared-sp.txt
#
# No MFA required - service principals bypass MFA enforcement.

set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
secrets_file="${project_root}/secrets/shared-sp.txt"
env_file="${project_root}/.env"
learner_prefix=''

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
  case "$1" in
    --secrets-file)
      if [[ $# -lt 2 ]]; then
        printf '[FAIL] --secrets-file requires a path\n' >&2
        return 2 2>/dev/null || exit 2
      fi
      secrets_file="$2"; shift 2 ;;
    -h|--help) sed -n '2,12p' "${BASH_SOURCE[0]}"; return 0 2>/dev/null || exit 0 ;;
    *) learner_prefix="$1"; shift ;;
  esac
done

if [[ -z "$learner_prefix" ]]; then
  printf 'Usage: source %s <LearnerPrefix> [--secrets-file <path>]\n' "${BASH_SOURCE[0]}" >&2
  printf '  LearnerPrefix: APP01 to APP10\n' >&2
  return 2 2>/dev/null || exit 2
fi

if [[ ! "$learner_prefix" =~ ^APP[0-9]{2}$ ]]; then
  printf '[FAIL] Invalid prefix: %s (expected APP01-APP10)\n' "$learner_prefix" >&2
  return 2 2>/dev/null || exit 2
fi

# ------------------------------------------------------------------
# Load .env (same project-level settings as Learner-Login.ps1)
# ------------------------------------------------------------------

declare -A env_values
trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

if [[ -f "$env_file" ]]; then
  printf '[INFO] Loading .env from %s\n' "$env_file"
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    line="$(trim_whitespace "$line")"
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    key="$(trim_whitespace "${line%%=*}")"
    value="$(trim_whitespace "${line#*=}")"
    if [[ ( "$value" == \"*\" && "$value" == *\" ) || ( "$value" == \'*\' && "$value" == *\' ) ]]; then
      value="${value:1:${#value}-2}"
    fi
    if [[ -n "$key" && -n "$value" && -z "${env_values[$key]:-}" ]]; then
      env_values["$key"]="$value"
      export "$key=$value"
    fi
  done < "$env_file"

  for var_name in ARM_RESOURCE_GROUP ARM_STORAGE_ACCOUNT ARM_CONTAINER; do
    if [[ -z "${!var_name:-}" ]]; then
      printf '[WARN] %s is empty or not set. Add it to .env if needed for Azure labs.\n' "$var_name" >&2
    fi
  done
else
  printf '[WARN] No .env file found at %s\n' "$env_file" >&2
  printf '       Copy .env.example to .env and fill in learner-specific values.\n' >&2
fi

# ------------------------------------------------------------------
# Check and parse shared SP file
# ------------------------------------------------------------------

if [[ ! -f "$secrets_file" ]]; then
  printf '[FAIL] Shared SP file not found: %s\n' "$secrets_file" >&2
  printf '       Ask your instructor for the shared-sp.txt file\n' >&2
  return 1 2>/dev/null || exit 1
fi

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
    return 1 2>/dev/null || exit 1
  fi
done

# ------------------------------------------------------------------
# Login and exports
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
  return 1 2>/dev/null || exit 1
fi

az account set --subscription "${creds[ARM_SUBSCRIPTION_ID]}" >/dev/null 2>&1
sub_name=$(az account show --query 'name' -o tsv 2>/dev/null)
printf '[PASS] Logged in to Azure\n'
printf '       Subscription: %s (%s)\n' "$sub_name" "${creds[ARM_SUBSCRIPTION_ID]}"
printf '       Tenant: %s\n' "${creds[ARM_TENANT_ID]}"
printf '       Learner prefix: %s\n\n' "$learner_prefix"

export ARM_CLIENT_ID="${creds[ARM_CLIENT_ID]}"
export ARM_CLIENT_SECRET="${creds[ARM_CLIENT_SECRET]}"
export ARM_TENANT_ID="${creds[ARM_TENANT_ID]}"
export ARM_SUBSCRIPTION_ID="${creds[ARM_SUBSCRIPTION_ID]}"
export LEARNER_PREFIX="$learner_prefix"

printf '[PASS] Environment variables set (ARM_CLIENT_SECRET hidden).\n'
printf '       LEARNER_PREFIX = %s\n\n' "$learner_prefix"
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  printf '[WARN] This script was executed, so its exports will not persist.\n' >&2
  printf '       Run: source ./scripts/learner-login.sh %s\n' "$learner_prefix" >&2
else
  printf '[PASS] Script sourced: exports persist in the current shell.\n'
fi
printf '\n============================================================\n'
printf ' Ready for labs\n'
printf '============================================================\n\n'
printf 'Next steps:\n'
printf '  ./scripts/test-lab-connectivity.sh --skip-devops\n\n'
