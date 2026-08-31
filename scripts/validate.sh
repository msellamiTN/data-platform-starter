#!/usr/bin/env bash
#
# Local validation script for the data-platform-starter project (Linux/macOS).
#
# Runs terraform fmt, validate and tflint on all environment roots.
# Nothing is deployed. No secret is read or displayed.
#
# Usage:
#   ./scripts/validate.sh

set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
environments="${root}/environments"

if [[ ! -d "$environments" ]]; then
  printf '[FAIL] environments/ directory not found\n'
  exit 1
fi

has_failures=false

printf '== terraform fmt -check -recursive ==\n'
terraform fmt -check -recursive "$environments"
if [[ $? -ne 0 ]]; then
  has_failures=true
  printf '[FAIL] Formatting issues detected\n'
else
  printf '[PASS] Formatting is clean\n'
fi

for env_dir in "$environments"/*/; do
  [[ -d "$env_dir" ]] || continue
  env_name="$(basename "$env_dir")"

  if ! ls "${env_dir}"*.tf >/dev/null 2>&1; then
    printf '[SKIP] %s : no .tf files yet\n' "$env_name"
    continue
  fi

  printf '== %s : terraform validate ==\n' "$env_name"
  (
    cd "$env_dir"
    terraform init -backend=false -input=false -no-color >/dev/null 2>&1
    terraform validate -no-color
    if [[ $? -ne 0 ]]; then
      printf '[FAIL] %s : validation failed\n' "$env_name"
    else
      printf '[PASS] %s : validation succeeded\n' "$env_name"
    fi
  )
done

if command -v tflint >/dev/null 2>&1; then
  printf '== tflint ==\n'
  tflint -c "${root}/.tflint.hcl" "$environments"
  if [[ $? -ne 0 ]]; then
    has_failures=true
    printf '[WARN] tflint reported issues\n'
  else
    printf '[PASS] tflint is clean\n'
  fi
else
  printf '[SKIP] tflint not installed\n'
fi

if $has_failures; then
  printf '\nValidation: FAILED\n'
  exit 1
fi

printf '\nValidation: PASSED\n'
exit 0
