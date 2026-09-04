#!/usr/bin/env bash
# reset-lab.sh — Reset a specific lab environment.
#
# Usage: ./scripts/reset-lab.sh --learner-prefix APP01 --lab M05 [--environment DEV]
#
# Destroys Terraform resources and drops leftover Snowflake objects for the
# specified lab only. Other labs' resources are untouched.

set -euo pipefail

LEARNER_PREFIX=""
LAB=""
ENVIRONMENT="DEV"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --learner-prefix) LEARNER_PREFIX="$2"; shift 2 ;;
        --lab)            LAB="$2"; shift 2 ;;
        --environment)    ENVIRONMENT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [[ -z "$LEARNER_PREFIX" || -z "$LAB" ]]; then
    echo "Usage: $0 --learner-prefix APP01 --lab M05 [--environment DEV]"
    exit 1
fi

# Normalize
LAB=$(echo "$LAB" | tr '[:lower:]' '[:upper:]')
ENVIRONMENT=$(echo "$ENVIRONMENT" | tr '[:lower:]' '[:upper:]')

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Map lab IDs to directory names
declare -A LAB_DIRS
LAB_DIRS=(
    ["M01"]="m01-iac-workflow"
    ["M02"]="m02-state-management"
    ["M03"]="m03-import-brownfield"
    ["M04"]="m04-variables-outputs"
    ["M05"]="m05-modules"
    ["M06"]="m06-dynamic-logic"
    ["M07"]="m07-cicd-pipeline"
    ["M08"]="m08-environments"
    ["M09"]="m09-snowflake-advanced"
    ["M10"]="m10-security-auth"
    ["M11"]="m11-rbac"
    ["M12"]="m12-capstone"
    ["M13"]="m13-finops-observability"
    ["M14"]="m14-data-products"
)

LAB_DIR_NAME="${LAB_DIRS[$LAB]:-}"
if [[ -z "$LAB_DIR_NAME" ]]; then
    echo "[ERROR] Unknown lab: $LAB. Valid values: M01-M14."
    exit 1
fi

LAB_DIR="$PROJECT_ROOT/labs/$LAB_DIR_NAME"

echo ""
echo "============================================================"
echo " Lab Reset: $LAB"
echo "============================================================"
echo ""
echo "  Learner prefix : $LEARNER_PREFIX"
echo "  Lab            : $LAB ($LAB_DIR_NAME)"
echo "  Environment    : $ENVIRONMENT"
echo "  Lab directory  : labs/$LAB_DIR_NAME"
echo ""

# 1. Terraform destroy
if [[ -d "$LAB_DIR" && -f "$LAB_DIR/terraform.tfstate" ]]; then
    echo "[1/3] Running terraform destroy in labs/$LAB_DIR_NAME..."
    (
        cd "$LAB_DIR"
        terraform destroy -auto-approve 2>&1 || true
    )
    echo "[OK]   terraform destroy done"
else
    echo "[1/3] No terraform.tfstate in labs/$LAB_DIR_NAME — skipping"
fi

# 2. Drop leftover Snowflake resources
echo ""
echo "[2/3] Dropping leftover Snowflake resources for $LAB..."

# Databases
for db in \
    "${LEARNER_PREFIX}_${LAB}_RAW_${ENVIRONMENT}" \
    "${LEARNER_PREFIX}_${LAB}_BROWNFIELD_${ENVIRONMENT}" \
    "DB_${LEARNER_PREFIX}_${LAB}_BROWNFIELD_${ENVIRONMENT}" \
    "${LEARNER_PREFIX}_${LAB}_SALES_${ENVIRONMENT}" \
    "${LEARNER_PREFIX}_${LAB}_FINANCE_${ENVIRONMENT}" \
    "${LEARNER_PREFIX}SAL_${LAB}_RAW_${ENVIRONMENT}"; do
    result=$(snow sql -c training -q "DROP DATABASE IF EXISTS \"$db\"" 2>&1 || true)
    echo "[SKIP] Database not found: $db"
done

# Warehouses
for wh in \
    "WH_${LEARNER_PREFIX}_${LAB}_ETL_${ENVIRONMENT}" \
    "WH_${LEARNER_PREFIX}SAL_${LAB}_ETL_${ENVIRONMENT}" \
    "WH_${LEARNER_PREFIX}_${LAB}_FINOPS_${ENVIRONMENT}"; do
    result=$(snow sql -c training -q "DROP WAREHOUSE IF EXISTS \"$wh\"" 2>&1 || true)
    echo "[SKIP] Warehouse not found: $wh"
done

# 3. Clean local state files
echo ""
echo "[3/3] Cleaning local state files..."

if [[ -d "$LAB_DIR" ]]; then
    cd "$LAB_DIR"
    rm -f terraform.tfstate terraform.tfstate.backup *.tfplan .terraform.lock.hcl
    rm -rf .terraform/
    echo "[OK]   State files cleaned"
else
    echo "[OK]   Lab directory does not exist"
fi

echo ""
echo "============================================================"
echo " Lab $LAB reset complete"
echo "============================================================"
echo ""
echo "Next steps:"
echo "  cd labs/$LAB_DIR_NAME"
echo "  terraform init"
echo "  terraform plan"
echo ""
