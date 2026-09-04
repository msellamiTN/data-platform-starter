#!/usr/bin/env bash
# ============================================================
# test-terraform-ready.sh — Pre-flight check before terraform plan
# ============================================================
# Verifies that:
# 1. Current directory is a Terraform root (has .tf files)
# 2. secrets/snowflake_pat.txt exists (two levels up)
# 3. TF_VAR_snowflake_token is set OR the PAT file is readable
# 4. LEARNER_PREFIX is set
# 5. ARM_SUBSCRIPTION_ID is set
#
# Usage: ./scripts/test-terraform-ready.sh
# Run from environments/dev/ or any terraform root.
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

all_ok=true

check_ok()   { echo "[OK]   $1"; }
check_fail() { echo "[FAIL] $1"; all_ok=false; }
check_warn() { echo "[WARN] $1"; }

echo ""
echo "============================================================"
echo " Terraform Pre-Flight Check"
echo "============================================================"
echo ""

# 1. Check current directory has .tf files
tf_count=$(find . -maxdepth 1 -name '*.tf' 2>/dev/null | wc -l)
if [ "$tf_count" -gt 0 ]; then
    check_ok "Terraform files found in current directory ($tf_count .tf files)"
else
    check_fail "No .tf files in current directory. Run from environments/dev/ or similar."
fi

# 2. Check PAT file exists
pat_file="$PROJECT_ROOT/secrets/snowflake_pat.txt"
if [ -f "$pat_file" ]; then
    pat_len=$(wc -c < "$pat_file" | tr -d ' ')
    check_ok "PAT file exists: secrets/snowflake_pat.txt ($pat_len chars)"
else
    check_warn "PAT file not found: secrets/snowflake_pat.txt (OK if using Key Vault)"
fi

# 3. Check TF_VAR_snowflake_token
if [ -n "${TF_VAR_snowflake_token:-}" ]; then
    check_ok "TF_VAR_snowflake_token is set"
else
    if [ -f "$pat_file" ]; then
        check_warn "TF_VAR_snowflake_token not set — terraform plan will read from PAT file"
    else
        check_fail "TF_VAR_snowflake_token not set and no PAT file — terraform plan will prompt"
    fi
fi

# 4. Check LEARNER_PREFIX
if [ -n "${LEARNER_PREFIX:-}" ]; then
    check_ok "LEARNER_PREFIX is set: $LEARNER_PREFIX"
else
    check_fail "LEARNER_PREFIX is not set. Run: ./scripts/learner-login.sh APPXX"
fi

# 5. Check ARM_SUBSCRIPTION_ID
if [ -n "${ARM_SUBSCRIPTION_ID:-}" ]; then
    check_ok "ARM_SUBSCRIPTION_ID is set"
else
    check_fail "ARM_SUBSCRIPTION_ID is not set. Run: ./scripts/learner-login.sh APPXX"
fi

# 6. Check ARM_CLIENT_ID
if [ -n "${ARM_CLIENT_ID:-}" ]; then
    check_ok "ARM_CLIENT_ID is set"
else
    check_fail "ARM_CLIENT_ID is not set. Run: ./scripts/learner-login.sh APPXX"
fi

# 7. Check terraform is available
if command -v terraform &>/dev/null; then
    tf_ver=$(terraform version 2>/dev/null | head -1)
    check_ok "Terraform available: $tf_ver"
else
    check_fail "Terraform not found in PATH. Run: ./scripts/install-tools.sh"
fi

echo ""
if [ "$all_ok" = true ]; then
    echo "============================================================"
    echo " READY — you can run: terraform plan"
    echo "============================================================"
    exit 0
else
    echo "============================================================"
    echo " NOT READY — fix FAIL items above before terraform plan"
    echo "============================================================"
    exit 1
fi
