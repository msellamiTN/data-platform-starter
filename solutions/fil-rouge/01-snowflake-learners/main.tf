# ============================================================
# 01-snowflake-learners — Main
# ============================================================
# Creates Snowflake users for each learner, grants SYSADMIN role,
# sets MFA bypass, and optionally stores passwords in Key Vault.
#
# PATs are NOT created here — Snowflake provider v2.14.0 has no
# snowflake_user_programmatic_access_token resource. Use
# Set-SnowflakePATs.ps1 to generate PATs and store them in Key Vault.
# ============================================================

# ============================================================
# Provider — uses instructor's ACCOUNTADMIN PAT
# ============================================================

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  authenticator     = "PROGRAMMATIC_ACCESS_TOKEN"
  token             = var.snowflake_token
  role              = var.snowflake_role
}

provider "azurerm" {
  subscription_id = "8c42d5b2-ab70-4051-ab0e-a96877557f6a"
  features {}
}

# ============================================================
# Locals — generate learner maps
# ============================================================

locals {
  learners = {
    for i in range(1, var.learner_count + 1) :
    format("APP%02d", i) => {
      index    = i
      username = replace(var.learner_username_pattern, "{i}", format("%02d", i))
      password = replace(var.learner_password_pattern, "{i}", format("%02d", i))
      prefix   = format("APP%02d", i)
    }
  }
}

# ============================================================
# Snowflake users
# ============================================================

resource "snowflake_user" "learners" {
  for_each = local.learners

  name                 = each.value.username
  password             = each.value.password
  default_role         = var.default_role
  must_change_password = tostring(var.must_change_password)
  mins_to_bypass_mfa   = var.mins_to_bypass_mfa
  disabled             = "false"
}

# ============================================================
# Grant SYSADMIN role to each learner
# ============================================================

resource "snowflake_grant_account_role" "sysadmin" {
  for_each = snowflake_user.learners

  role_name = var.default_role
  user_name = each.value.name
}

# ============================================================
# Store learner web passwords in Key Vault (optional)
# ============================================================

resource "azurerm_key_vault_secret" "learner_passwords" {
  for_each = var.store_passwords_in_kv ? local.learners : {}

  name         = "SnowflakePassword-${each.key}"
  value        = each.value.password
  key_vault_id = var.key_vault_id
}
