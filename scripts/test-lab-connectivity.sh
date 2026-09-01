#!/usr/bin/env bash
#
# Tests connectivity to all services used in the training labs.
#
# Verifies that the learner can reach:
# - Snowflake (via snow CLI connection)
# - Azure CLI (authenticated session)
# - Azure Blob Storage (Terraform backend)
# - Azure Key Vault (secret storage)
# - Azure DevOps (CI/CD pipelines)
# - Git (local and remote)
# - Terraform (initialized provider)
#
# Usage:
#   ./scripts/test-lab-connectivity.sh
#   ./scripts/test-lab-connectivity.sh --skip-azure --skip-devops
#   ./scripts/test-lab-connectivity.sh --report-path ./reports/connectivity

set -uo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
env_file="${project_root}/.env"

# ------------------------------------------------------------------
# Load .env
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
fi

# ------------------------------------------------------------------
# Arguments
# ------------------------------------------------------------------

skip_azure=false
skip_devops=false
report_path="${script_dir}/../reports/connectivity"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-azure)  skip_azure=true; shift ;;
    --skip-devops) skip_devops=true; shift ;;
    --report-path) report_path="$2"; shift 2 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) printf 'Unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

# ------------------------------------------------------------------
# Helpers
# ------------------------------------------------------------------

get_config_value() {
  local key="$1" default="${2:-}"
  if [[ -n "${env_values[$key]:-}" ]]; then printf '%s' "${env_values[$key]}"; return 0; fi
  if [[ -n "$default" ]]; then printf '%s' "$default"; return 0; fi
  printf ''
}

has_tool() { command -v "$1" >/dev/null 2>&1; }

pass_count=0
fail_count=0
warn_count=0
skip_count=0

current_section=''
results_file=''

# Initialize results temp file
results_file=$(mktemp)

set_section() {
  current_section="$1"
}

test_step() {
  local name="$1" status="$2" detail="${3:-}"
  local color
  case "$status" in
    PASS) color='\033[0;32m'; ((pass_count++)) ;;
    FAIL) color='\033[0;31m'; ((fail_count++)) ;;
    WARN) color='\033[0;33m'; ((warn_count++)) ;;
    SKIP) color='\033[0;90m'; ((skip_count++)) ;;
  esac
  printf "  ${color}[%s]${color} %s\033[0m\n" "$status" "$name"
  if [[ -n "$detail" ]]; then
    printf "         %s\n" "$detail" >&2
  fi
  # Record to results file (tab-separated: section<TAB>name<TAB>status<TAB>detail)
  local clean_detail="${detail//|//}"
  printf '%s\t%s\t%s\t%s\n' "$current_section" "$name" "$status" "$clean_detail" >> "$results_file"
}

# ------------------------------------------------------------------
# Header
# ------------------------------------------------------------------

printf '\n============================================================\n'
printf ' Lab Connectivity Test\n'
printf '============================================================\n\n'

# ------------------------------------------------------------------
# 1. CLI tools
# ------------------------------------------------------------------

set_section '1. CLI Tools'
printf '== 1. CLI Tools\n'

if has_tool git; then
  test_step 'Git' 'PASS' "$(git --version 2>&1)"
else
  test_step 'Git' 'FAIL' 'Not found'
fi

if has_tool terraform; then
  test_step 'Terraform' 'PASS' "$(terraform version 2>&1 | head -1)"
else
  test_step 'Terraform' 'FAIL' 'Not found'
fi

if has_tool snow; then
  test_step 'Snowflake CLI' 'PASS' "$(snow --version 2>&1 | head -1)"
else
  test_step 'Snowflake CLI' 'FAIL' 'Not found'
fi

if has_tool az; then
  test_step 'Azure CLI' 'PASS' 'Available'
else
  test_step 'Azure CLI' 'FAIL' 'Not found'
fi

if has_tool python3 || has_tool python; then
  local_py="python3"
  has_tool python3 || local_py="python"
  test_step 'Python' 'PASS' "$($local_py --version 2>&1)"
else
  test_step 'Python' 'FAIL' 'Not found'
fi

if has_tool dbt; then
  test_step 'dbt' 'PASS' "$(dbt --version 2>&1 | head -1)"
else
  test_step 'dbt' 'WARN' 'Not found (required from Day 4)'
fi

if has_tool tflint; then
  test_step 'tflint' 'PASS' 'Available'
else
  test_step 'tflint' 'WARN' 'Not found (optional)'
fi

# ------------------------------------------------------------------
# 2. Snowflake connectivity
# ------------------------------------------------------------------

set_section '2. Snowflake Connectivity'
printf '\n== 2. Snowflake Connectivity\n'

connection_name="$(get_config_value 'SNOWFLAKE_CONNECTION' 'training')"

# Check snow CLI config
snow_config_file="${HOME}/.config/snowflake/config.toml"
if [[ ! -f "$snow_config_file" ]]; then
  snow_config_file="${HOME}/.snowflake/config.toml"
fi

if [[ -f "$snow_config_file" ]]; then
  if grep -q "connections\.$connection_name" "$snow_config_file" 2>/dev/null; then
    test_step "Snow CLI connection '$connection_name'" 'PASS' 'Found in config.toml'
  else
    test_step "Snow CLI connection '$connection_name'" 'FAIL' 'Not found - run new-snowflake-connection.sh'
  fi
else
  test_step "Snow CLI connection '$connection_name'" 'FAIL' 'No config.toml found'
fi

# Check PAT file
pat_file_rel="$(get_config_value 'SNOWFLAKE_PAT_FILE' 'secrets/snowflake_pat.txt')"
pat_file_path="${project_root}/${pat_file_rel}"

if [[ -f "$pat_file_path" ]]; then
  pat_len=$(wc -c < "$pat_file_path" | tr -d '[:space:]')
  if [[ "$pat_len" -gt 10 ]]; then
    test_step 'PAT file' 'PASS' "$pat_file_rel ($pat_len chars)"
  else
    test_step 'PAT file' 'FAIL' "$pat_file_rel appears empty"
  fi
else
  test_step 'PAT file' 'FAIL' "$pat_file_rel not found"
fi

# Test Snowflake query
if has_tool snow; then
  snow_result=$(snow sql -q 'SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_ACCOUNT()' -c "$connection_name" --format=json 2>&1)
  snow_exit=$?
  clean_result=$(echo "$snow_result" | grep -v 'Warning\|UserWarning\|encoding' | head -5)
  if [[ $snow_exit -eq 0 ]] && [[ -n "$clean_result" ]]; then
    test_step 'Snowflake query' 'PASS' "$clean_result"
  else
    test_step 'Snowflake query' 'FAIL' "Exit code $snow_exit"
  fi
else
  test_step 'Snowflake query' 'SKIP' 'snow CLI not installed'
fi

# ------------------------------------------------------------------
# 3. Azure connectivity
# ------------------------------------------------------------------

set_section '3. Azure Connectivity'
printf '\n== 3. Azure Connectivity\n'

if $skip_azure; then
  test_step 'Azure tests' 'SKIP' 'Skipped by --skip-azure'
elif ! has_tool az; then
  test_step 'Azure tests' 'SKIP' 'Azure CLI not installed'
else
  # -- 3a. Azure CLI authentication --
  az_account=$(az account show --query 'name' -o tsv 2>/dev/null)
  if [[ $? -eq 0 ]] && [[ -n "$az_account" ]]; then
    az_sub_id=$(az account show --query 'id' -o tsv 2>/dev/null)
    az_tenant=$(az account show --query 'tenantId' -o tsv 2>/dev/null)
    test_step 'Azure CLI authentication' 'PASS' "Subscription: $az_account ($az_sub_id)"
    test_step 'Azure tenant' 'PASS' "Tenant: $az_tenant"
  else
    test_step 'Azure CLI authentication' 'FAIL' "Not logged in - run 'az login'"
  fi

  # -- 3b. Subscription match --
  arm_sub_id="$(get_config_value 'ARM_SUBSCRIPTION_ID')"
  if [[ -n "$arm_sub_id" ]]; then
    current_sub_id=$(az account show --query 'id' -o tsv 2>/dev/null)
    if [[ "$current_sub_id" == "$arm_sub_id" ]]; then
      test_step 'Subscription match' 'PASS' 'Current subscription matches ARM_SUBSCRIPTION_ID'
    else
      test_step 'Subscription match' 'WARN' "Current sub=$current_sub_id, .env expects=$arm_sub_id"
    fi
  else
    test_step 'Subscription match' 'SKIP' 'ARM_SUBSCRIPTION_ID not set'
  fi

  # -- 3c. Service principal --
  arm_client_id="$(get_config_value 'ARM_CLIENT_ID')"
  arm_tenant_id="$(get_config_value 'ARM_TENANT_ID')"
  if [[ -n "$arm_client_id" ]] && [[ -n "$arm_tenant_id" ]]; then
    sp_check=$(az ad sp show --id "$arm_client_id" --query 'appId' -o tsv 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$sp_check" ]]; then
      test_step 'Service principal' 'PASS' "App ID: $arm_client_id"
    else
      test_step 'Service principal' 'FAIL' "SP not found: $arm_client_id"
    fi
  else
    test_step 'Service principal' 'SKIP' 'ARM_CLIENT_ID or ARM_TENANT_ID not set'
  fi

  # -- 3d. Resource group --
  arm_rg="$(get_config_value 'ARM_RESOURCE_GROUP')"
  if [[ -n "$arm_rg" ]]; then
    rg_check=$(az group show --name "$arm_rg" --query 'name' -o tsv 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$rg_check" ]]; then
      rg_location=$(az group show --name "$arm_rg" --query 'location' -o tsv 2>/dev/null)
      test_step 'Resource group' 'PASS' "$arm_rg ($rg_location)"
    else
      test_step 'Resource group' 'FAIL' "Not found: $arm_rg"
    fi
  else
    test_step 'Resource group' 'SKIP' 'ARM_RESOURCE_GROUP not set'
  fi

  # -- 3e. Storage Account and Blob container --
  arm_sa="$(get_config_value 'ARM_STORAGE_ACCOUNT')"
  arm_container="$(get_config_value 'ARM_CONTAINER' 'tfstate')"
  if [[ -n "$arm_sa" ]] && [[ -n "$arm_rg" ]]; then
    sa_check=$(az storage account show --name "$arm_sa" --resource-group "$arm_rg" --query 'name' -o tsv 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$sa_check" ]]; then
      sa_sku=$(az storage account show --name "$arm_sa" --resource-group "$arm_rg" --query 'sku.name' -o tsv 2>/dev/null)
      test_step 'Azure Storage Account' 'PASS' "$arm_sa (SKU: $sa_sku)"
      container_exists=$(az storage container exists --name "$arm_container" --account-name "$arm_sa" --query 'exists' -o tsv 2>/dev/null)
      if [[ $? -eq 0 ]] && [[ "$container_exists" == 'true' ]]; then
        test_step 'Azure Blob Container' 'PASS' "$arm_container"
      else
        test_step 'Azure Blob Container' 'WARN' "Container '$arm_container' not found - created by terraform init"
      fi

      # Test write access
      probe_name="connectivity-probe-$(date +%Y%m%d%H%M%S).txt"
      probe_temp="/tmp/$probe_name"
      echo 'connectivity-test' > "$probe_temp"
      az storage blob upload --account-name "$arm_sa" --container-name "$arm_container" --name "$probe_name" --file "$probe_temp" --overwrite true >/dev/null 2>&1
      if [[ $? -eq 0 ]]; then
        test_step 'Blob write access' 'PASS' 'Probe uploaded and deleted'
        az storage blob delete --account-name "$arm_sa" --container-name "$arm_container" --name "$probe_name" >/dev/null 2>&1
        rm -f "$probe_temp"
      else
        test_step 'Blob write access' 'FAIL' 'Cannot write to container - check RBAC'
        rm -f "$probe_temp"
      fi
    else
      test_step 'Azure Storage Account' 'FAIL' "Not found: $arm_sa in $arm_rg"
    fi
  else
    test_step 'Azure Storage Account' 'SKIP' 'ARM_STORAGE_ACCOUNT or ARM_RESOURCE_GROUP not set'
  fi

  # -- 3f. Key Vault --
  kv_name="$(get_config_value 'KEY_VAULT_NAME')"
  kv_rg="$(get_config_value 'KEY_VAULT_RESOURCE_GROUP')"
  if [[ -n "$kv_name" ]]; then
    kv_check=$(az keyvault show --name "$kv_name" --resource-group "$kv_rg" --query 'name' -o tsv 2>/dev/null)
    if [[ $? -eq 0 ]] && [[ -n "$kv_check" ]]; then
      kv_uri=$(az keyvault show --name "$kv_name" --resource-group "$kv_rg" --query 'properties.vaultUri' -o tsv 2>/dev/null)
      test_step 'Azure Key Vault' 'PASS' "$kv_name ($kv_uri)"
      secret_list=$(az keyvault secret list --vault-name "$kv_name" --query '[].name' -o tsv 2>/dev/null)
      if [[ $? -eq 0 ]] && [[ -n "$secret_list" ]]; then
        secret_count=$(echo "$secret_list" | wc -l | tr -d '[:space:]')
        test_step 'Key Vault secrets' 'PASS' "$secret_count secret(s) accessible"
      else
        test_step 'Key Vault secrets' 'WARN' 'No secrets or no access'
      fi
    else
      test_step 'Azure Key Vault' 'WARN' 'Not found (used from Day 4)'
    fi
  else
    test_step 'Azure Key Vault' 'SKIP' 'KEY_VAULT_NAME not set'
  fi
fi

# ------------------------------------------------------------------
# 4. Azure DevOps
# ------------------------------------------------------------------

set_section '4. Azure DevOps Connectivity'
printf '\n== 4. Azure DevOps Connectivity\n'

if $skip_devops; then
  test_step 'Azure DevOps tests' 'SKIP' 'Skipped by --skip-devops'
else
  ado_org="$(get_config_value 'ADO_ORGANIZATION')"
  ado_project="$(get_config_value 'ADO_PROJECT')"
  ado_sc="$(get_config_value 'ADO_SERVICE_CONNECTION')"

  if [[ -z "$ado_org" ]] || [[ "$ado_org" =~ ^\< ]]; then
    test_step 'Azure DevOps' 'SKIP' 'ADO_ORGANIZATION not set (used from Day 5)'
  elif ! has_tool az; then
    test_step 'Azure DevOps' 'SKIP' 'Azure CLI required for DevOps tests'
  else
    # -- 4a. DevOps CLI extension --
    ext_check=$(az extension list --query "[?name=='azure-devops'].name" -o tsv 2>/dev/null)
    if [[ -n "$ext_check" ]]; then
      test_step 'Azure DevOps CLI extension' 'PASS' 'azure-devops installed'
    else
      test_step 'Azure DevOps CLI extension' 'WARN' 'Not installed - run: az extension add --name azure-devops'
    fi

    # -- 4b. Organization URL --
    if [[ "$ado_org" =~ ^https?:// ]]; then
      ado_org_url="$ado_org"
    else
      ado_org_url="https://dev.azure.com/$ado_org"
    fi
    test_step 'DevOps organization URL' 'PASS' "$ado_org_url"

    # -- 4c. DevOps PAT --
    if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" ]]; then
      test_step 'DevOps PAT' 'PASS' 'AZURE_DEVOPS_EXT_PAT is set'
    else
      test_step 'DevOps PAT' 'WARN' 'AZURE_DEVOPS_EXT_PAT not set'
    fi

    # -- 4d. DevOps project (REST API) --
    if [[ -n "${AZURE_DEVOPS_EXT_PAT:-}" ]] && [[ -n "$ado_project" ]]; then
      encoded_project=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ado_project'))" 2>/dev/null || echo "$ado_project")
      api_url="${ado_org_url}/_apis/projects/${encoded_project}?api-version=7.1"
      pat_token=$(echo -n ":${AZURE_DEVOPS_EXT_PAT}" | base64)
      project_resp=$(curl -s -w "\n%{http_code}" -H "Authorization: Basic $pat_token" "$api_url" 2>/dev/null)
      http_code=$(echo "$project_resp" | tail -1)
      project_body=$(echo "$project_resp" | sed '$d')
      if [[ "$http_code" == "200" ]]; then
        project_name=$(echo "$project_body" | grep -o '"name":"[^"]*"' | head -1 | sed 's/"name":"//;s/"//')
        project_id=$(echo "$project_body" | grep -o '"id":"[^"]*"' | head -1 | sed 's/"id":"//;s/"//')
        test_step 'DevOps project' 'PASS' "Project: $project_name (id: $project_id)"
      elif [[ "$http_code" == "404" ]]; then
        test_step 'DevOps project' 'FAIL' "Project not found: $ado_project"
      elif [[ "$http_code" == "401" ]]; then
        test_step 'DevOps project' 'FAIL' 'Unauthorized - check PAT permissions'
      else
        test_step 'DevOps project' 'WARN' "HTTP $http_code - cannot verify"
      fi

      # -- 4e. Repositories --
      repo_url="${ado_org_url}/${encoded_project}/_apis/git/repositories?api-version=7.1"
      repo_resp=$(curl -s -w "\n%{http_code}" -H "Authorization: Basic $pat_token" "$repo_url" 2>/dev/null)
      repo_code=$(echo "$repo_resp" | tail -1)
      repo_body=$(echo "$repo_resp" | sed '$d')
      if [[ "$repo_code" == "200" ]]; then
        repo_count=$(echo "$repo_body" | grep -o '"count":[0-9]*' | head -1 | sed 's/"count"://')
        if [[ "$repo_count" -gt 0 ]] 2>/dev/null; then
          repo_names=$(echo "$repo_body" | grep -o '"name":"[^"]*"' | sed 's/"name":"//;s/"//' | head -3 | tr '\n' ', ' | sed 's/,$//')
          test_step 'DevOps repositories' 'PASS' "$repo_count repo(s): $repo_names"
        else
          test_step 'DevOps repositories' 'WARN' 'No repositories found'
        fi
      else
        test_step 'DevOps repositories' 'WARN' "HTTP $repo_code"
      fi

      # -- 4f. Pipelines --
      pipe_url="${ado_org_url}/${encoded_project}/_apis/pipelines?api-version=7.1"
      pipe_resp=$(curl -s -w "\n%{http_code}" -H "Authorization: Basic $pat_token" "$pipe_url" 2>/dev/null)
      pipe_code=$(echo "$pipe_resp" | tail -1)
      pipe_body=$(echo "$pipe_resp" | sed '$d')
      if [[ "$pipe_code" == "200" ]]; then
        pipe_count=$(echo "$pipe_body" | grep -o '"count":[0-9]*' | head -1 | sed 's/"count"://')
        if [[ "$pipe_count" -gt 0 ]] 2>/dev/null; then
          test_step 'DevOps pipelines' 'PASS' "$pipe_count pipeline(s) found"
        else
          test_step 'DevOps pipelines' 'WARN' 'No pipelines found - created in Day 5'
        fi
      else
        test_step 'DevOps pipelines' 'WARN' 'No pipelines yet (created in Day 5)'
      fi
    else
      test_step 'DevOps project' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test project access'
      test_step 'DevOps repositories' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test repo access'
      test_step 'DevOps pipelines' 'SKIP' 'Set AZURE_DEVOPS_EXT_PAT to test pipeline access'
    fi

    # -- 4g. Service connection --
    if [[ -n "$ado_sc" ]]; then
      test_step 'Service connection' 'PASS' "Configured: $ado_sc"
    else
      test_step 'Service connection' 'SKIP' 'ADO_SERVICE_CONNECTION not set'
    fi
  fi
fi

# ------------------------------------------------------------------
# 5. Git and repository
# ------------------------------------------------------------------

set_section '5. Git and Repository'
printf '\n== 5. Git and Repository\n'

if [[ -d "${project_root}/.git" ]]; then
  git_remote=$(git -C "$project_root" remote get-url origin 2>/dev/null)
  if [[ $? -eq 0 ]] && [[ -n "$git_remote" ]]; then
    test_step 'Git remote' 'PASS' "$git_remote"
  else
    test_step 'Git remote' 'WARN' 'No origin remote'
  fi

  git_branch=$(git -C "$project_root" branch --show-current 2>/dev/null)
  if [[ $? -eq 0 ]] && [[ -n "$git_branch" ]]; then
    test_step 'Git branch' 'PASS' "$git_branch"
  else
    test_step 'Git branch' 'WARN' 'Could not determine'
  fi
else
  test_step 'Git repository' 'WARN' 'Not a git repository'
fi

# Check .env is gitignored
if git -C "$project_root" check-ignore .env >/dev/null 2>&1; then
  test_step '.env is gitignored' 'PASS' 'Protected'
else
  test_step '.env is gitignored' 'FAIL' '.env is NOT ignored'
fi

# Check secrets/ is gitignored
if git -C "$project_root" check-ignore secrets/snowflake_pat.txt >/dev/null 2>&1; then
  test_step 'secrets/ is gitignored' 'PASS' 'Protected'
else
  test_step 'secrets/ is gitignored' 'FAIL' 'secrets/ is NOT ignored'
fi

# ------------------------------------------------------------------
# 6. Terraform environment
# ------------------------------------------------------------------

set_section '6. Terraform Environment'
printf '\n== 6. Terraform Environment\n'

dev_dir="${project_root}/environments/dev"
tf_count=$(find "$dev_dir" -maxdepth 1 -name '*.tf' 2>/dev/null | wc -l | tr -d '[:space:]')

if [[ "$tf_count" -gt 0 ]]; then
  test_step 'Terraform files in environments/dev' 'PASS' "$tf_count .tf files"

  if [[ -d "${dev_dir}/.terraform" ]]; then
    test_step 'Terraform init' 'PASS' '.terraform/ exists'
    if [[ -f "${dev_dir}/.terraform.lock.hcl" ]]; then
      test_step 'Provider lock file' 'PASS' '.terraform.lock.hcl exists'
    else
      test_step 'Provider lock file' 'WARN' 'No .terraform.lock.hcl'
    fi
  else
    test_step 'Terraform init' 'WARN' 'Not initialized - run terraform init'
  fi
else
  test_step 'Terraform files in environments/dev' 'SKIP' 'No .tf files yet'
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

printf '\n============================================================\n'
printf ' Summary\n'
printf '============================================================\n\n'
printf '  PASS : %d\n' "$pass_count"
printf '  FAIL : %d\n' "$fail_count"
printf '  WARN : %d\n' "$warn_count"
printf '  SKIP : %d\n' "$skip_count"
printf '\n'

# ------------------------------------------------------------------
# Determine overall status
# ------------------------------------------------------------------

overall_status='READY'
if [[ $fail_count -gt 0 ]]; then
  overall_status='NOT READY'
elif [[ $warn_count -gt 0 ]]; then
  overall_status='READY (with warnings)'
fi

# ------------------------------------------------------------------
# Report
# ------------------------------------------------------------------

if true; then
  markdown_path="${report_path}.md"
  json_path="${report_path}.json"

  report_dir="$(dirname "$markdown_path")"
  if [[ -n "$report_dir" ]] && [[ ! -d "$report_dir" ]]; then
    mkdir -p "$report_dir"
  fi

  # Markdown report
  {
    printf '# Lab Connectivity Report\n\n'
    printf 'Generated: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf 'Project: %s\n' "$project_root"
    printf 'Status: %s\n\n' "$overall_status"
    printf '| Section | Name | Status | Detail |\n'
    printf '|---|---|---|---|\n'
    while IFS=$'\t' read -r sec name stat det; do
      printf '| %s | %s | %s | %s |\n' "$sec" "$name" "$stat" "$det"
    done < "$results_file"
    printf '\nPASS: %d | FAIL: %d | WARN: %d | SKIP: %d\n' "$pass_count" "$fail_count" "$warn_count" "$skip_count"
  } > "$markdown_path"

  # JSON report
  {
    printf '{\n'
    printf '  "generated": "%s",\n' "$(date '+%Y-%m-%dT%H:%M:%S')"
    printf '  "project": "%s",\n' "$project_root"
    printf '  "status": "%s",\n' "$overall_status"
    printf '  "summary": {\n'
    printf '    "PASS": %d,\n' "$pass_count"
    printf '    "FAIL": %d,\n' "$fail_count"
    printf '    "WARN": %d,\n' "$warn_count"
    printf '    "SKIP": %d\n' "$skip_count"
    printf '  },\n'
    printf '  "results": [\n'
    first=true
    while IFS=$'\t' read -r sec name stat det; do
      if $first; then first=false; else printf ',\n'; fi
      printf '    {"section": "%s", "name": "%s", "status": "%s", "detail": "%s"}' \
        "${sec//\"/\\\"}" "${name//\"/\\\"}" "$stat" "${det//\"/\\\"}"
    done < "$results_file"
    printf '\n  ]\n'
    printf '}\n'
  } > "$json_path"

  printf 'Report: %s\n' "$markdown_path" >&2
  printf 'Report: %s\n' "$json_path" >&2
  printf '\n' >&2
fi

# Cleanup temp file
rm -f "$results_file"

if [[ $fail_count -gt 0 ]]; then
  printf 'Status: %s - fix FAIL items before starting labs\n' "$overall_status"
  exit 1
elif [[ $warn_count -gt 0 ]]; then
  printf 'Status: %s - review WARN items\n' "$overall_status"
  exit 0
else
  printf 'Status: %s - all checks passed\n' "$overall_status"
  exit 0
fi
