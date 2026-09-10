# ============================================================
# 01-snowflake-learners — Outputs
# ============================================================

output "learner_usernames" {
  value = {
    for k, v in snowflake_user.learners :
    k => v.name
  }
  description = "Map of learner prefix to Snowflake username."
}

output "learner_count" {
  value       = length(snowflake_user.learners)
  description = "Number of learner users created."
}

output "role_grants" {
  value = {
    for k, v in snowflake_grant_account_role.sysadmin :
    k => "${var.default_role} -> ${v.user_name}"
  }
  description = "Map of learner prefix to role grant string."
}

output "key_vault_secret_names" {
  value = var.store_passwords_in_kv ? {
    for k, v in azurerm_key_vault_secret.learner_passwords :
    k => v.name
  } : {}
  description = "Map of learner prefix to Key Vault secret name (if stored)."
}

output "pat_setup_reminder" {
  value = {
    for k, v in snowflake_user.learners :
    k => "snow sql -q \"ALTER USER ${v.name} ADD PROGRAMMATIC_ACCESS_TOKEN\" --role ACCOUNTADMIN"
  }
  description = "SQL commands to generate PATs (run via Set-SnowflakePATs.ps1). Snowflake provider v2.14.0 has no PAT resource."
}
