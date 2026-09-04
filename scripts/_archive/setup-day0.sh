#!/usr/bin/env bash
set -u

scenario='SANDBOX'
connection='terraform_svc'
skip_snowflake=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --scenario) scenario="${2^^}"; shift 2 ;;
    --connection) connection="$2"; shift 2 ;;
    --skip-snowflake) skip_snowflake=true; shift ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done
[[ "$scenario" == 'SANDBOX' || "$scenario" == 'TRIAL' ]] || { printf 'Scenario must be SANDBOX or TRIAL\n' >&2; exit 2; }

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
failed=0

check() {
  local name="$1" condition="$2" detail="$3" required="${4:-true}"
  if eval "$condition"; then
    printf '[PASS] %s - %s\n' "$name" "$detail"
  elif [[ "$required" == true ]]; then
    printf '[FAIL] %s - %s\n' "$name" "$detail"
    failed=$((failed + 1))
  else
    printf '[WARN] %s - %s\n' "$name" "$detail"
  fi
}

printf 'Day 0 - non-destructive preflight\nScenario: %s\nRepository: %s\n\n' "$scenario" "$repo_root"
check 'Git' 'command -v git >/dev/null 2>&1' 'available in PATH'
check 'Terraform' 'command -v terraform >/dev/null 2>&1' 'available in PATH'
check 'Snowflake CLI' 'command -v snow >/dev/null 2>&1' 'available in PATH'
check 'VS Code' 'command -v code >/dev/null 2>&1' 'optional editor' false
check '.env.example' 'test -f "$repo_root/.env.example"' 'public configuration template'
check '.gitignore' 'test -f "$repo_root/.gitignore"' 'local secret protection'
check '.env local' 'test -f "$repo_root/.env"' 'copy .env.example and replace placeholders'
if [[ -f "$repo_root/.env" ]]; then
  check 'Configuration completed' '! grep -Eq "<[^>]+>" "$repo_root/.env"' 'no <placeholder> may remain'
fi
check '.env ignored by Git' 'git -C "$repo_root" check-ignore .env >/dev/null 2>&1' 'local file must stay untracked'
check 'secrets/ ignored by Git' 'git -C "$repo_root" check-ignore secrets/probe.token >/dev/null 2>&1' 'credentials must stay outside Git'
if $skip_snowflake; then
  printf '[WARN] Snowflake connection - remote test explicitly skipped\n'
else
  check 'Snowflake connection' 'command -v snow >/dev/null 2>&1 && snow connection test -c "$connection" >/dev/null 2>&1' "connection '$connection'"
fi

printf '\n'
if (( failed == 0 )); then
  printf 'Ready for Day 1\n'
  exit 0
fi
printf 'Not ready: %d required check(s) failed.\n' "$failed"
printf 'Open courses/day-00/module-00-setup/troubleshooting.md and rerun this script.\n'
exit 1
