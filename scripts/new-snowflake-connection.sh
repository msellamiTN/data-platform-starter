#!/usr/bin/env bash
#
# Creates a Snowflake CLI connection using credentials from .env.
#
# All Snowflake parameters come from .env. The PAT is read from
# SNOWFLAKE_PAT in .env, or from the file pointed to by SNOWFLAKE_PAT_FILE.
# If neither is available, the script prompts for it with a masked input.
#
# The token is written to secrets/snowflake_pat.txt and the connection is
# created with --token-file-path so that 'snow sql -c training' works
# standalone without exporting SNOWFLAKE_PAT each time.
#
# The PAT is never displayed, never logged, and never passed as a
# command-line argument.
#
# Usage:
#   ./scripts/new-snowflake-connection.sh

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
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    [[ -z "$key" ]] && continue
    key="${key//[[:space:]]/}"
    value="${value//[[:space:]]/}"
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    env_values["$key"]="$value"
  done < "$env_file"
else
  printf '[WARN] No .env file found at %s\n' "$env_file" >&2
  printf '       Copy .env.example to .env and fill in your values.\n' >&2
  exit 1
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

read_masked() {
  local prompt="$1" value
  printf '%s ' "$prompt" >&2
  read -rs value
  printf '\n' >&2
  printf '%s' "$value"
}

# ------------------------------------------------------------------
# Resolve all parameters from .env
# ------------------------------------------------------------------

printf '\n============================================================\n'
printf ' Snowflake CLI connection setup\n'
printf '============================================================\n\n'

connection_name="$(get_config_value 'SNOWFLAKE_CONNECTION' "$connection_name" 'training')"
organization="$(get_config_value 'SNOWFLAKE_ORGANIZATION' "$organization")"
account="$(get_config_value 'SNOWFLAKE_ACCOUNT' "$account")"
user="$(get_config_value 'SNOWFLAKE_USER' "$user")"
role="$(get_config_value 'SNOWFLAKE_ROLE' "$role" 'SYSADMIN')"
host="$(get_config_value 'SNOWFLAKE_HOST' "$host")"
pat_file_rel="$(get_config_value 'SNOWFLAKE_PAT_FILE' '' 'secrets/snowflake_pat.txt')"

# Show resolved values (without secrets)
printf '  Connection : %s\n' "$connection_name" >&2
printf '  Account    : %s-%s\n' "$organization" "$account" >&2
printf '  User       : %s\n' "$user" >&2
printf '  Role       : %s\n' "$role" >&2
if [[ -n "$host" ]]; then
  printf '  Host       : %s\n' "$host" >&2
fi
printf '  Token file : %s\n' "$pat_file_rel" >&2
printf '\n' >&2

# Validate required values
missing=()
[[ -z "$organization" ]] && missing+=('SNOWFLAKE_ORGANIZATION')
[[ -z "$account" ]]      && missing+=('SNOWFLAKE_ACCOUNT')
[[ -z "$user" ]]         && missing+=('SNOWFLAKE_USER')

if [[ ${#missing[@]} -gt 0 ]]; then
  printf '[ERROR] Missing required values in .env:\n' >&2
  for m in "${missing[@]}"; do
    printf '       - %s\n' "$m" >&2
  done
  printf '       Edit .env and fill in these values.\n' >&2
  exit 1
fi

# ------------------------------------------------------------------
# Resolve PAT: .env variable > file > prompt
# ------------------------------------------------------------------

pat_file_path="${project_root}/${pat_file_rel}"
token="${env_values['SNOWFLAKE_PAT']:-}"

if [[ -z "$token" ]] && [[ -f "$pat_file_path" ]]; then
  printf '[INFO] Reading PAT from %s\n' "$pat_file_rel" >&2
  token="$(cat "$pat_file_path" | tr -d '[:space:]')"
fi

if [[ -z "$token" ]]; then
  printf '[INFO] SNOWFLAKE_PAT not found in .env or PAT file.\n' >&2
  token="$(read_masked 'Enter Snowflake PAT (token):')"
fi

if [[ -z "$token" ]]; then
  printf '[ERROR] No token available. Aborting.\n' >&2
  exit 1
fi

# ------------------------------------------------------------------
# Write the token to the PAT file so the connection can find it
# ------------------------------------------------------------------

pat_dir="$(dirname "$pat_file_path")"
if [[ ! -d "$pat_dir" ]]; then
  mkdir -p "$pat_dir"
fi

if [[ ! -f "$pat_file_path" ]] || [[ "$(cat "$pat_file_path" | tr -d '[:space:]')" != "$token" ]]; then
  printf '[INFO] Writing PAT to %s\n' "$pat_file_rel" >&2
  printf '%s' "$token" > "$pat_file_path"
fi

# ------------------------------------------------------------------
# Build the snow connection add command
# The --token-file-path stores the path in config.toml so that
# 'snow sql -c training' reads the token from the file automatically.
# ------------------------------------------------------------------

snow_args=(connection add -n "$connection_name" -a "${organization}-${account}" -u "$user" -r "$role" -A PROGRAMMATIC_ACCESS_TOKEN -t "$pat_file_path" --no-interactive)

if [[ -n "$host" ]]; then
  snow_args+=(-h "$host")
fi

# ------------------------------------------------------------------
# Drop existing connection if it already exists (idempotent)
# ------------------------------------------------------------------

if snow connection remove "$connection_name" 2>/dev/null; then
  printf '[INFO] Removed existing connection '%s'.\n' "$connection_name" >&2
fi

# ------------------------------------------------------------------
# Create the connection
# ------------------------------------------------------------------

printf 'Creating the connection...\n'

if snow "${snow_args[@]}" 2>&1; then
  printf "[OK] Connection '%s' created.\n" "$connection_name"
else
  printf "[ERROR] snow connection add failed with exit code %d\n" "$?"
  exit 1
fi

# ------------------------------------------------------------------
# Test the connection — no env var needed, token comes from file
# ------------------------------------------------------------------

printf '\nTesting the connection...\n'

if snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' -c "$connection_name" --format=json 2>&1; then
  printf '[OK] Connection test succeeded.\n'
else
  printf '[WARN] Connection created but test query failed.\n'
  printf "       Check with: snow connection test -c %s\n" "$connection_name"
fi

printf '\nDone.\n'
printf '\nNext steps:\n'
printf "  - Use the connection:  snow sql -q 'SELECT 1' -c %s\n" "$connection_name"
printf '  - The token is read from the file automatically — no env var needed.\n'
printf '  - Do not store the PAT in any committed file (secrets/ is gitignored).\n'
printf '  - Rotate the PAT when the training module is complete.\n'
