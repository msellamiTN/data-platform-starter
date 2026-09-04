#!/usr/bin/env bash
#
# Installs and verifies the Terraform and Snowflake training toolchain on
# Linux and macOS. Versions come from docs/version-policy.md.
#
# The script is idempotent. Python based tools are installed in an isolated
# virtual environment instead of the system interpreter. Terraform and tflint
# are installed under the user profile so root access is not required.
#
# When an installation is blocked, the official manual procedure is printed and
# the script continues instead of failing hard.
#
# Exit code 0 means every required tool is available.
#
# Usage:
#   ./scripts/install-tools.sh --check
#   ./scripts/install-tools.sh
#   ./scripts/install-tools.sh --report-path ./preflight

set -uo pipefail

# ------------------------------------------------------------------
# Versions - keep aligned with docs/version-policy.md
# ------------------------------------------------------------------

POLICY_TERRAFORM='1.14.5'
POLICY_PYTHON='3.12'
POLICY_AZURE_CLI='2.83.0'
POLICY_TFLINT='0.50.0'
POLICY_SNOWFLAKE_CLI='3.23.0'
POLICY_DBT_SPEC='<3.0.0'

# Terraform providers (installed via terraform init, not by this script)
declare -A PROVIDER_VERSIONS=(
  ['snowflakedb/snowflake']='2.14.0'
  ['hashicorp/azurerm']='4.59.0'
  ['microsoft/azuredevops']='1.14.0'
  ['hashicorp/tls']='>= 4.0'
)

# dbt packages (installed via dbt deps, not by this script)
declare -A DBT_PACKAGES=(
  ['get-select/dbt_snowflake_monitoring']='4.6.0'
  ['dbt-labs/dbt_utils']='1.3.3'
)

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

check_only=false
force=false
skip_optional=false
report_path=''
install_root="${HOME}/.data2ai"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) check_only=true; shift ;;
    --force) force=true; shift ;;
    --skip-optional) skip_optional=true; shift ;;
    --report-path) report_path="$2"; shift 2 ;;
    --install-root) install_root="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

bin_dir="${install_root}/bin"
venv_dir="${install_root}/venv"
venv_bin="${venv_dir}/bin"
dbt_venv_dir="${install_root}/venv-dbt"
dbt_venv_bin="${dbt_venv_dir}/bin"

names=()
tiers=()
statuses=()
details=()
actions=()

# ------------------------------------------------------------------
# Platform detection
# ------------------------------------------------------------------

case "$(uname -s)" in
  Linux) os='linux' ;;
  Darwin) os='darwin' ;;
  *) printf 'Unsupported operating system: %s\n' "$(uname -s)" >&2; exit 2 ;;
esac

case "$(uname -m)" in
  x86_64|amd64) arch='amd64' ;;
  arm64|aarch64) arch='arm64' ;;
  *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 2 ;;
esac

# ------------------------------------------------------------------
# Output helpers
# ------------------------------------------------------------------

section() { printf '\n== %s\n' "$1"; }

sanitize_detail() {
  # Remove pipes so the Markdown table stays valid, collapse whitespace, truncate.
  printf '%s' "$1" | tr '|' '/' | tr -s '[:space:]' ' ' | cut -c1-90
}

add_result() {
  local name="$1" tier="$2" status="$3" detail="$4" action="${5:-}"
  detail="$(sanitize_detail "$detail")"
  names+=("$name"); tiers+=("$tier"); statuses+=("$status")
  details+=("$detail"); actions+=("$action")
  printf '[%s] %s - %s\n' "$status" "$name" "$detail"
  [[ -n "$action" ]] && printf '       %s\n' "$action"
  return 0
}

has_tool() { command -v "$1" >/dev/null 2>&1; }

tool_version() {
  local name="$1"; shift
  has_tool "$name" || return 1

  local output status
  output="$("$name" "$@" 2>&1)"
  status=$?
  [[ $status -ne 0 ]] && return 1

  # Reject output that only reports an execution failure.
  case "$output" in
    *'Exec format error'*|*'cannot execute'*|*'not recognized'*) return 1 ;;
  esac

  printf '%s' "$output" | sed -n '/[^[:space:]]/{p;q;}'
}

manual_step() {
  case "$1" in
    Git) printf 'Install Git with your distribution package manager or the official installer, then open a new terminal.' ;;
    Terraform) printf 'Download Terraform %s for %s_%s from the official HashiCorp releases site and place the binary in a folder listed in PATH.' "$POLICY_TERRAFORM" "$os" "$arch" ;;
    Python) printf 'Install Python %s with your package manager or the official python.org installer.' "$POLICY_PYTHON" ;;
    'Snowflake CLI') printf 'Install Snowflake CLI >= %s with pip: pip install "snowflake-cli>=%s" inside a Python virtual environment.' "$POLICY_SNOWFLAKE_CLI" "$POLICY_SNOWFLAKE_CLI" ;;
    dbt) printf 'Install dbt-core and dbt-snowflake (both below version 3) inside a Python virtual environment.' ;;
    'Azure CLI') printf 'Install Azure CLI with the official Microsoft procedure for your distribution.' ;;
    tflint) printf 'Download tflint %s for %s_%s from the official releases page.' "$POLICY_TFLINT" "$os" "$arch" ;;
    'VS Code') printf 'Install Visual Studio Code from the official Microsoft download page, or use another editor.' ;;
    OpenSSL) printf 'Install the openssl package with your package manager.' ;;
    *) printf 'Install this tool with the vendor official procedure.' ;;
  esac
}

add_user_path_hint() {
  local directory="$1"
  case ":${PATH}:" in
    *":${directory}:"*) ;;
    *) export PATH="${directory}:${PATH}"
       printf '       Add this to your shell profile: export PATH="%s:$PATH"\n' "$directory" ;;
  esac
}

install_from_zip() {
  local name="$1" url="$2" executable="$3"
  local archive staging
  archive="$(mktemp -t "${name}.XXXXXX.zip")"
  staging="$(mktemp -d -t "${name}.XXXXXX")"

  mkdir -p "$bin_dir"

  if ! curl -fsSL "$url" -o "$archive"; then
    rm -rf "$archive" "$staging"
    return 1
  fi

  if ! unzip -oq "$archive" -d "$staging" 2>/dev/null; then
    rm -rf "$archive" "$staging"
    return 1
  fi

  local found
  found="$(find "$staging" -type f -name "$executable" | head -n 1)"
  if [[ -z "$found" ]]; then
    rm -rf "$archive" "$staging"
    return 1
  fi

  install -m 0755 "$found" "${bin_dir}/${executable}"
  rm -rf "$archive" "$staging"
  add_user_path_hint "$bin_dir"
  return 0
}

package_install() {
  local package="$1"
  if has_tool apt-get && has_tool sudo; then
    sudo apt-get update -qq && sudo apt-get install -y -qq "$package" >/dev/null 2>&1
  elif has_tool dnf && has_tool sudo; then
    sudo dnf install -y -q "$package" >/dev/null 2>&1
  elif has_tool brew; then
    brew install "$package" >/dev/null 2>&1
  else
    return 1
  fi
}

python_command() {
  if has_tool python3; then printf 'python3'
  elif has_tool python; then printf 'python'
  else return 1; fi
}

init_venv() {
  local py
  py="$(python_command)" || return 1
  if [[ ! -x "${venv_bin}/python" ]]; then
    printf '       Creating the isolated virtual environment...\n' >&2
    "$py" -m venv "$venv_dir" 2>&1 | sed 's/^/       /' >&2
  fi
  # Always ensure the venv bin dir is in PATH
  add_user_path_hint "$venv_bin"
  [[ -x "${venv_bin}/python" ]]
}

install_venv_package() {
  [[ -x "${venv_bin}/python" ]] || return 1
  printf '       Upgrading pip...\n' >&2
  "${venv_bin}/python" -m pip install --upgrade pip 2>&1 | sed 's/^/       /' >&2
  printf '       Installing: %s\n' "$*" >&2
  "${venv_bin}/python" -m pip install "$@" 2>&1 | sed 's/^/       /' >&2
  return $?
}

init_dbt_venv() {
  local py
  py="$(python_command)" || return 1
  if [[ ! -x "${dbt_venv_bin}/python" ]]; then
    printf '       Creating the dbt virtual environment...\n' >&2
    "$py" -m venv "$dbt_venv_dir" 2>&1 | sed 's/^/       /' >&2
  fi
  add_user_path_hint "$dbt_venv_bin"
  [[ -x "${dbt_venv_bin}/python" ]]
}

install_dbt_venv_package() {
  [[ -x "${dbt_venv_bin}/python" ]] || return 1
  printf '       Upgrading pip...\n' >&2
  "${dbt_venv_bin}/python" -m pip install --upgrade pip 2>&1 | sed 's/^/       /' >&2
  printf '       Installing: %s\n' "$*" >&2
  "${dbt_venv_bin}/python" -m pip install "$@" 2>&1 | sed 's/^/       /' >&2
  return $?
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

if $check_only; then mode='CHECK (no installation)'; else mode='INSTALL'; fi

printf '\n============================================================\n'
printf ' Terraform and Snowflake training toolchain\n'
printf '============================================================\n'
printf ' Mode         : %s\n' "$mode"
printf ' Platform     : %s_%s\n' "$os" "$arch"
printf ' Install root : %s\n' "$install_root"
printf ' Policy       : docs/version-policy.md\n'

[[ -d "$bin_dir" ]] && add_user_path_hint "$bin_dir"
[[ -d "$venv_bin" ]] && add_user_path_hint "$venv_bin"
[[ -d "$dbt_venv_bin" ]] && add_user_path_hint "$dbt_venv_bin"

# ------------------------------------------------------------------
# Git
# ------------------------------------------------------------------

section 'Git'
git_version="$(tool_version git --version || true)"

if [[ -n "$git_version" ]] && ! $force; then
  add_result 'Git' 'Core' 'PASS' "$git_version"
elif $check_only; then
  add_result 'Git' 'Core' 'FAIL' 'Not found' "$(manual_step Git)"
else
  package_install git || true
  git_version="$(tool_version git --version || true)"
  if [[ -n "$git_version" ]]; then
    add_result 'Git' 'Core' 'PASS' "$git_version"
  else
    add_result 'Git' 'Core' 'FAIL' 'Installation did not complete' "$(manual_step Git)"
  fi
fi

# ------------------------------------------------------------------
# Terraform
# ------------------------------------------------------------------

section "Terraform ${POLICY_TERRAFORM}"
tf_version="$(tool_version terraform version || true)"

if [[ "$tf_version" == *"$POLICY_TERRAFORM"* ]] && ! $force; then
  add_result 'Terraform' 'Core' 'PASS' "$tf_version"
elif $check_only; then
  if [[ -n "$tf_version" ]]; then
    add_result 'Terraform' 'Core' 'FAIL' "Found ${tf_version}, policy requires ${POLICY_TERRAFORM}" "$(manual_step Terraform)"
  else
    add_result 'Terraform' 'Core' 'FAIL' 'Not found' "$(manual_step Terraform)"
  fi
else
  url="https://releases.hashicorp.com/terraform/${POLICY_TERRAFORM}/terraform_${POLICY_TERRAFORM}_${os}_${arch}.zip"
  install_from_zip terraform "$url" terraform || true
  tf_version="$(tool_version terraform version || true)"
  if [[ "$tf_version" == *"$POLICY_TERRAFORM"* ]]; then
    add_result 'Terraform' 'Core' 'PASS' "$tf_version"
  else
    add_result 'Terraform' 'Core' 'FAIL' "${tf_version:-Installation did not complete}" "$(manual_step Terraform)"
  fi
fi

# ------------------------------------------------------------------
# Python
# ------------------------------------------------------------------

section "Python ${POLICY_PYTHON}"
py_cmd="$(python_command || true)"
py_version=''
[[ -n "$py_cmd" ]] && py_version="$(tool_version "$py_cmd" --version || true)"

if [[ "$py_version" == *"$POLICY_PYTHON"* ]]; then
  add_result 'Python' 'Core' 'PASS' "$py_version"
elif [[ -n "$py_version" ]]; then
  add_result 'Python' 'Core' 'WARN' "Found ${py_version}, policy requires ${POLICY_PYTHON}" "$(manual_step Python)"
elif $check_only; then
  add_result 'Python' 'Core' 'FAIL' 'Not found' "$(manual_step Python)"
else
  package_install python3 || true
  py_cmd="$(python_command || true)"
  [[ -n "$py_cmd" ]] && py_version="$(tool_version "$py_cmd" --version || true)"
  if [[ -n "$py_version" ]]; then
    add_result 'Python' 'Core' 'PASS' "$py_version"
  else
    add_result 'Python' 'Core' 'FAIL' 'Installation did not complete' "$(manual_step Python)"
  fi
fi

# ------------------------------------------------------------------
# Snowflake CLI
# ------------------------------------------------------------------

section "Snowflake CLI >= ${POLICY_SNOWFLAKE_CLI}"
snow_version="$(tool_version snow --version || true)"

# Check if snow version meets the minimum (3.23.0+ for PAT support)
snow_version_ok=false
if [[ -n "$snow_version" ]]; then
  snow_major=$(echo "$snow_version" | grep -oP '\d+\.\d+\.\d+' | head -1 | cut -d. -f1)
  snow_minor=$(echo "$snow_version" | grep -oP '\d+\.\d+\.\d+' | head -1 | cut -d. -f2)
  policy_major=$(echo "$POLICY_SNOWFLAKE_CLI" | cut -d. -f1)
  policy_minor=$(echo "$POLICY_SNOWFLAKE_CLI" | cut -d. -f2)
  if [[ "$snow_major" -gt "$policy_major" ]] || ([[ "$snow_major" -eq "$policy_major" ]] && [[ "$snow_minor" -ge "$policy_minor" ]]); then
    snow_version_ok=true
  fi
fi

if $snow_version_ok && ! $force; then
  add_result 'Snowflake CLI' 'Core' 'PASS' "$snow_version"
elif $check_only; then
  if [[ -n "$snow_version" ]]; then
    add_result 'Snowflake CLI' 'Core' 'FAIL' "Found ${snow_version}, policy requires >= ${POLICY_SNOWFLAKE_CLI} (PAT support)" "$(manual_step 'Snowflake CLI')"
  else
    add_result 'Snowflake CLI' 'Core' 'FAIL' 'Not found' "$(manual_step 'Snowflake CLI')"
  fi
else
  if init_venv && install_venv_package "snowflake-cli>=${POLICY_SNOWFLAKE_CLI}"; then
    add_user_path_hint "$venv_bin"
  fi
  snow_version="$(tool_version snow --version || true)"
  if [[ -n "$snow_version" ]]; then
    add_result 'Snowflake CLI' 'Core' 'PASS' "$snow_version"
  else
    add_result 'Snowflake CLI' 'Core' 'FAIL' 'Installation did not complete' "$(manual_step 'Snowflake CLI')"
  fi
fi

# ------------------------------------------------------------------
# dbt
# ------------------------------------------------------------------

section "dbt ${POLICY_DBT_SPEC}"
dbt_version="$(tool_version dbt --version || true)"

if [[ -n "$dbt_version" ]] && ! $force; then
  add_result 'dbt' 'Course' 'PASS' "$dbt_version"
elif $check_only; then
  add_result 'dbt' 'Course' 'FAIL' 'Not found (required from Day 5)' "$(manual_step dbt)"
else
  if init_dbt_venv && install_dbt_venv_package "dbt-core${POLICY_DBT_SPEC}" "dbt-snowflake${POLICY_DBT_SPEC}"; then
    add_user_path_hint "$dbt_venv_bin"
  fi
  dbt_version="$(tool_version dbt --version || true)"
  if [[ -n "$dbt_version" ]]; then
    add_result 'dbt' 'Course' 'PASS' "$dbt_version"
  else
    add_result 'dbt' 'Course' 'FAIL' 'Installation did not complete' "$(manual_step dbt)"
  fi
fi

# ------------------------------------------------------------------
# Azure CLI
# ------------------------------------------------------------------

section "Azure CLI ${POLICY_AZURE_CLI}"
az_available=false
has_tool az && az_available=true

if $az_available && ! $force; then
  add_result 'Azure CLI' 'Course' 'PASS' 'Available'
elif $check_only; then
  add_result 'Azure CLI' 'Course' 'FAIL' 'Not found (required from Day 2)' "$(manual_step 'Azure CLI')"
else
  package_install azure-cli || true
  if has_tool az; then
    add_result 'Azure CLI' 'Course' 'PASS' 'Available'
  else
    add_result 'Azure CLI' 'Course' 'FAIL' 'Installation did not complete' "$(manual_step 'Azure CLI')"
  fi
fi

# ------------------------------------------------------------------
# Optional tools
# ------------------------------------------------------------------

if $skip_optional; then
  section 'Optional tools'
  add_result 'Optional tools' 'Optional' 'SKIP' 'Skipped by request'
else
  section "tflint ${POLICY_TFLINT}"
  tflint_version="$(tool_version tflint --version || true)"
  if [[ -n "$tflint_version" ]] && ! $force; then
    add_result 'tflint' 'Optional' 'PASS' "$tflint_version"
  elif $check_only; then
    add_result 'tflint' 'Optional' 'WARN' 'Not found' "$(manual_step tflint)"
  else
    url="https://github.com/terraform-linters/tflint/releases/download/v${POLICY_TFLINT}/tflint_${os}_${arch}.zip"
    install_from_zip tflint "$url" tflint || true
    tflint_version="$(tool_version tflint --version || true)"
    if [[ -n "$tflint_version" ]]; then
      add_result 'tflint' 'Optional' 'PASS' "$tflint_version"
    else
      add_result 'tflint' 'Optional' 'WARN' 'Installation did not complete' "$(manual_step tflint)"
    fi
  fi

  section 'VS Code'
  # Detect VS Code without invoking it: on WSL the Windows binary may hang.
  if has_tool code; then
    add_result 'VS Code' 'Optional' 'PASS' 'Available'
  else
    add_result 'VS Code' 'Optional' 'WARN' 'Not found' "$(manual_step 'VS Code')"
  fi

  section 'OpenSSL'
  openssl_version="$(tool_version openssl version || true)"
  if [[ -n "$openssl_version" ]]; then
    add_result 'OpenSSL' 'Optional' 'PASS' "$openssl_version"
  else
    add_result 'OpenSSL' 'Optional' 'WARN' 'Not found' "$(manual_step OpenSSL)"
  fi
fi

# ------------------------------------------------------------------
# Terraform providers and dbt packages (informational)
# ------------------------------------------------------------------

section 'Terraform providers (installed by terraform init)'
for key in "${!PROVIDER_VERSIONS[@]}"; do
  printf '  %-40s %s\n' "$key" "${PROVIDER_VERSIONS[$key]}" >&2
done

section 'dbt packages (installed by dbt deps)'
for key in "${!DBT_PACKAGES[@]}"; do
  printf '  %-40s %s\n' "$key" "${DBT_PACKAGES[$key]}" >&2
done

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

core_failures=0
course_failures=0
warnings=0

for index in "${!names[@]}"; do
  case "${statuses[$index]}" in
    FAIL)
      if [[ "${tiers[$index]}" == 'Core' ]]; then
        core_failures=$((core_failures + 1))
      elif [[ "${tiers[$index]}" == 'Course' ]]; then
        course_failures=$((course_failures + 1))
      fi
      ;;
    WARN) warnings=$((warnings + 1)) ;;
  esac
done

section 'Summary'

if (( core_failures == 0 )); then
  printf 'Core tools (Day 1)      : READY\n'
else
  printf 'Core tools (Day 1)      : %d missing\n' "$core_failures"
fi

if (( course_failures == 0 )); then
  printf 'Course tools (Day 2-5)  : READY\n'
else
  printf 'Course tools (Day 2-5)  : %d missing\n' "$course_failures"
fi

printf 'Warnings                : %d\n' "$warnings"

if (( core_failures > 0 || course_failures > 0 )); then
  printf '\nAction required:\n'
  for index in "${!names[@]}"; do
    if [[ "${statuses[$index]}" == 'FAIL' && "${tiers[$index]}" != 'Optional' ]]; then
      printf '  - %s: %s\n' "${names[$index]}" "${actions[$index]}"
    fi
  done
fi

printf '\nIf a command is still not found, open a new terminal.\n'

# ------------------------------------------------------------------
# Report
# ------------------------------------------------------------------

if [[ -n "$report_path" ]]; then
  {
    printf '# Toolchain report\n\n'
    printf 'Mode: %s\n' "$mode"
    printf 'Generated: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '| Tool | Tier | Status | Detail |\n|---|---|---|---|\n'
    for index in "${!names[@]}"; do
      printf '| %s | %s | %s | %s |\n' "${names[$index]}" "${tiers[$index]}" "${statuses[$index]}" "${details[$index]}"
    done
    printf '\nCore failures: %d\n' "$core_failures"
    printf 'Course failures: %d\n' "$course_failures"
    printf 'Warnings: %d\n' "$warnings"
  } > "${report_path}.md"

  {
    printf '[\n'
    for index in "${!names[@]}"; do
      printf '  {"Name": "%s", "Tier": "%s", "Status": "%s", "Detail": "%s"}' \
        "${names[$index]}" "${tiers[$index]}" "${statuses[$index]}" "${details[$index]}"
      if (( index < ${#names[@]} - 1 )); then printf ',\n'; else printf '\n'; fi
    done
    printf ']\n'
  } > "${report_path}.json"

  printf '\nReport: %s.md\n' "$report_path"
  printf 'Report: %s.json\n' "$report_path"
fi

if (( core_failures > 0 )); then
  printf '\nToolchain status: NOT READY\n'
  exit 1
fi

printf '\nToolchain status: READY\n'
exit 0
