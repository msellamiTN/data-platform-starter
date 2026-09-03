#!/usr/bin/env bash
# ============================================================
# Add-SnowflakeLearners.sh
# Creates individual Snowflake users for each learner.
#
# For each learner:
#   - Creates a Snowflake user (apprenant01 to apprenant10)
#   - Sets a password (14+ chars, compliant with Snowflake policy)
#   - Grants SYSADMIN role
#
# Passwords are saved to secrets/learner-snowflake-passwords.txt (gitignored).
#
# Usage:
#   ./scripts/add-snowflake-learners.sh
#   ./scripts/add-snowflake-learners.sh --dry-run
#   ./scripts/add-snowflake-learners.sh --reset-passwords
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SECRETS_DIR="$PROJECT_ROOT/secrets"
SECRETS_FILE="$SECRETS_DIR/learner-snowflake-passwords.txt"

DRY_RUN=false
RESET_PASSWORDS=false

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --reset-passwords) RESET_PASSWORDS=true ;;
        *) echo "[WARN] Unknown argument: $arg" ;;
    esac
done

# ------------------------------------------------------------------
# Verify Snowflake CLI connection
# ------------------------------------------------------------------

echo "[INFO] Testing Snowflake connection..."

if ! snow sql -c training -q "SELECT 1" >/dev/null 2>&1; then
    echo "[FAIL] Snowflake CLI connection failed"
    echo "       Run new-snowflake-connection.sh first"
    exit 1
fi

echo "[PASS] Snowflake connection OK"
echo ""

# ------------------------------------------------------------------
# Learner list
# Password policy: 14+ chars, 1 digit, 1 uppercase, 1 lowercase
# Pattern: SnowflakeLearner2026@XX (24 chars)
# ------------------------------------------------------------------

LEARNER_COUNT=10
MODE="PROVISION"
if $DRY_RUN; then MODE="DRY RUN (no changes)"; fi

echo "============================================================"
echo " Snowflake Learner Users - $MODE"
echo "============================================================"
echo " Users: $LEARNER_COUNT"
echo " Role:  SYSADMIN"
echo ""

# ------------------------------------------------------------------
# Create each user
# ------------------------------------------------------------------

CREATED=0
EXISTING=0
FAILED=0
PASSWORD_LINES=()

PASSWORD_LINES+=("# Snowflake Learner Passwords")
PASSWORD_LINES+=("# Generated: $(date -u '+%Y-%m-%d %H:%M:%S') UTC")
PASSWORD_LINES+=("# Format: username|password")
PASSWORD_LINES+=("# Web login: https://app.snowflake.com")
PASSWORD_LINES+=("# Password policy: 14+ chars, 1 digit, 1 uppercase, 1 lowercase")
PASSWORD_LINES+=("")

for i in $(seq 1 $LEARNER_COUNT); do
    PADDED=$(printf '%02d' "$i")
    NAME="apprenant$PADDED"
    PASSWORD="SnowflakeLearner2026@$PADDED"

    echo "-- $NAME"

    # Check if user exists
    CHECK=$(snow sql -c training -q "SHOW USERS LIKE '$NAME'" 2>&1 || true)
    USER_EXISTS=false
    if echo "$CHECK" | grep -q "| $NAME |" || echo "$CHECK" | grep -qi "apprenant$PADDED"; then
        USER_EXISTS=true
    fi

    if $USER_EXISTS; then
        if $RESET_PASSWORDS; then
            echo "   [INFO] User exists, resetting password..."
            if snow sql -c training -q "ALTER USER $NAME SET PASSWORD='$PASSWORD'" >/dev/null 2>&1; then
                echo "   [PASS] Password reset"
            else
                echo "   [FAIL] Password reset failed"
                FAILED=$((FAILED + 1))
            fi
            EXISTING=$((EXISTING + 1))
        else
            echo "   [SKIP] User already exists (use --reset-passwords to update)"
            EXISTING=$((EXISTING + 1))
        fi
    elif $DRY_RUN; then
        echo "   [DRY] Would create user with SYSADMIN role"
        CREATED=$((CREATED + 1))
    else
        # Create user with password
        if snow sql -c training -q "CREATE USER $NAME PASSWORD='$PASSWORD' DEFAULT_ROLE='SYSADMIN' MUST_CHANGE_PASSWORD=FALSE" >/dev/null 2>&1; then
            echo "   [PASS] User created"
            CREATED=$((CREATED + 1))
        else
            echo "   [FAIL] User creation failed"
            FAILED=$((FAILED + 1))
            continue
        fi

        # Grant SYSADMIN role
        if snow sql -c training -q "GRANT ROLE SYSADMIN TO USER $NAME" >/dev/null 2>&1; then
            echo "   [PASS] SYSADMIN role granted"
        else
            echo "   [WARN] Role grant failed"
        fi
    fi

    PASSWORD_LINES+=("$NAME|$PASSWORD")
    echo ""
done

# ------------------------------------------------------------------
# Save passwords
# ------------------------------------------------------------------

if ! $DRY_RUN; then
    mkdir -p "$SECRETS_DIR"
    printf '%s\n' "${PASSWORD_LINES[@]}" > "$SECRETS_FILE"
    echo "Passwords saved to: $SECRETS_FILE"
    echo ""
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------

echo "============================================================"
echo " Summary"
echo "============================================================"
echo ""
echo "  Created      : $CREATED"
echo "  Already exist: $EXISTING"
echo "  Failed       : $FAILED"
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo "Status: PARTIAL"
    exit 1
else
    echo "Status: DONE"
    if ! $DRY_RUN; then
        echo ""
        echo "Learners can login to Snowflake web:"
        echo "  https://app.snowflake.com"
        echo "  Username: apprenant01 to apprenant10"
        echo "  Password: from $SECRETS_FILE"
        echo ""
        echo "Or via CLI:"
        echo "  snow sql -c training -q \"SELECT 1\" (uses shared PAT)"
    fi
    exit 0
fi
