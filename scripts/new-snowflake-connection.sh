#!/usr/bin/env bash
#
# Creates a Snowflake CLI connection using credentials from .env or a masked prompt.
#
# The script reads .env from the project root if it exists. It uses the
# Snowflake parameters found there. If a parameter is missing or .env does
# not exist, the script prompts for it interactively.
#
# The PAT is read from .env (SNOWFLAKE_PAT) or entered via a masked prompt.
# It is never displayed, never logged, and never passed as a command-line
# argument.
#
# Usage:
#   ./scripts/new-snowflake-connection.sh
#   ./scripts/new-snowflake-connection.sh -n training -o MYORG -a MYACCOUNT -u DATA2AI -r SYSADMIN

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
env_file="${project_root}/.env"

# ------------------------------------------------------------------
# Load .env if it exists
# ------------------------------------------------------------------

declare -A env_values

if [[ -f "$env_file" ]]; then
  printf '[INFO] Loading .env from %s\n' "$env_file" >&2
  while IFS='=' read -r key value; do
    # Skip comments and empty lines
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    # Trim whitespace and quotes
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    env_values["$key"]="$value"
  done < "$env_file"
else
  printf '[INFO] No .env file found. You will be prompted for all values.\n' >&2
fi

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

connection_name=''
organization=''
account=''
user=''
role=''
host=''

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--connection-name) connection_name="$2"; shift 2 ;;
    -o|--organization)    organization="$2"; shift 2 ;;
    -a|--account)         account="$2"; shift 2 ;;
    -u|--user)            user="$2"; shift 2 ;;
    -r|--role)            role="$2"; shift 2 ;;
    -h|--host)            host="$2"; shift 2 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

get_config_value() {
  local key="$1" override="$2" default="${3:-}"
  if [[ -n "$override" ]]; then printf '%s' "$override"; return 0; fi
  if [[ -n "${env_values[$key]:-}" ]]; then printf '%s' "${env_values[$key]}"; return 0; fi
  if [[ -n "$default" ]]; then printf '%s' "$default"; return 0; fi
  printf ''
}

read_required() {
  local prompt="$1" default="${2:-}" value
  while true; do
    printf '%s' "$prompt"
    [[ -n "$default" ]] && printf ' [%s]' "$default"
    printf ': '
    read -r value
    if [[ -n "$value" ]]; then printf '%s' "$value"; return 0; fi
    if [[ -n "$default" ]]; then printf '%s' "$default"; return 0; fi
    printf '  A value is required.\n' >&2
  done
}

read_masked() {
  local prompt="$1" value
  printf '%s ' "$prompt"
  read -rs value
  printf '\n'
  printf '%s' "$value"
}

# ------------------------------------------------------------------
# Resolve parameters
# ------------------------------------------------------------------

printf '\n============================================================\n'
printf ' Snowflake CLI connection setup\n'
printf '============================================================\n'
printf '\nThe PAT is read from .env or entered securely.\n'
printf 'It is never displayed or logged.\n\n'

connection_name="$(get_config_value 'SNOWFLAKE_CONNECTION' "$connection_name" 'training')"
organization="$(get_config_value 'SNOWFLAKE_ORGANIZATION' "$organization")"
account="$(get_config_value 'SNOWFLAKE_ACCOUNT' "$account")"
user="$(get_config_value 'SNOWFLAKE_USER' "$user")"
role="$(get_config_value 'SNOWFLAKE_ROLE' "$role" 'SYSADMIN')"
host="$(get_config_value 'SNOWFLAKE_HOST' "$host")"

[[ -z "$organization" ]] && organization="$(read_required 'Snowflake organization name')"
[[ -z "$account" ]]      && account="$(read_required 'Snowflake account name')"
[[ -z "$user" ]]         && user="$(read_required 'Snowflake user name')"

# PAT: try .env first, then prompt
token="${env_values['SNOWFLAKE_PAT']:-}"

if [[ -z "$token" ]]; then
  token="$(read_masked 'Snowflake PAT (token):')"
fi

if [[ -z "$token" ]]; then
  printf '[ERROR] No token available. Aborting.\n'
  exit 1
fi

# ------------------------------------------------------------------
# Build the snow connection add command
# ------------------------------------------------------------------

snow_args=(connection add -n "$connection_name" -a "$account" -o "$organization" -u "$user" -r "$role" --no-interactive)

if [[ -n "$host" ]]; then
  snow_args+=(-h "$host")
fi

export SNOWFLAKE_PAT="$token"

printf '\nCreating the connection...\n'

if snow "${snow_args[@]}" 2>&1; then
  printf "[OK] Connection '%s' created.\n" "$connection_name"
else
  printf "[ERROR] snow connection add failed with exit code %d\n" "$?"
  unset SNOWFLAKE_PAT
  exit 1
fi

# ------------------------------------------------------------------
# Test the connection
# ------------------------------------------------------------------

printf '\nTesting the connection...\n'

if snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' -c "$connection_name" --format=json 2>&1; then
  printf '[OK] Connection test succeeded.\n'
else
  printf '[WARN] Connection created but test query failed.\n'
  printf "       Check with: snow connection test -c %s\n" "$connection_name"
fi

unset SNOWFLAKE_PAT

printf '\nDone.\n'
printf '\nNext steps:\n'
printf "  - Use the connection:  snow sql -q 'SELECT 1' -c %s\n" "$connection_name"
printf '  - Do not store the PAT in any committed file.\n'
printf '  - Rotate the PAT when the training module is complete.\n'
