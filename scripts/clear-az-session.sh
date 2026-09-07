#!/usr/bin/env bash
# Clear all Azure connections and stale credentials from previous sessions.
# Bash twin of Clear-AzSession.ps1 — run this FIRST before learner-login.sh
# when switching accounts or when Terraform picks up the wrong SP.
set -u

echo "============================================================"
echo " Clearing previous Azure connections"
echo "============================================================"
echo

# 1-3. Azure CLI: logout + clear all cached accounts + purge cache
if command -v az >/dev/null 2>&1; then
    echo "[INFO] az logout ..."
    az logout 2>/dev/null || true

    echo "[INFO] az account clear (all cached accounts) ..."
    az account clear 2>/dev/null || true

    echo "[INFO] az cache purge ..."
    az cache purge 2>/dev/null || true

    echo "[PASS] Azure CLI sessions cleared"
else
    echo "[SKIP] az CLI not found in PATH"
fi

# 4. Clear leftover environment variables (session scope)
if [ "${1:-}" != "--keep-env" ]; then
    for v in \
        ARM_CLIENT_ID ARM_CLIENT_SECRET ARM_TENANT_ID ARM_SUBSCRIPTION_ID \
        ARM_USE_AZUREAD ARM_USE_OIDC ARM_ACCESS_KEY \
        TF_VAR_snowflake_token TF_VAR_rsa_public_key \
        LEARNER_PREFIX KEY_VAULT_NAME AZURE_CONFIG_DIR; do
        if [ -n "${!v:-}" ]; then
            unset "$v"
            echo "       cleared \$$v"
        fi
    done
    echo "[PASS] Session environment variables cleared"
else
    echo "[SKIP] --keep-env specified, env vars untouched"
fi

echo
echo "============================================================"
echo " Clean slate — run learner-login.sh to authenticate"
echo "============================================================"
echo
echo "Next step:"
echo "  ./scripts/learner-login.sh APP01"
