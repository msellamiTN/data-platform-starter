# Provider Snowflake
#
# The PAT is injected via the TF_VAR_snowflake_token environment variable
# by Learner-Login.ps1, which retrieves it from Azure Key Vault at login time.
#
# No secret file is read from disk. The token stays in memory.
#
# If TF_VAR_snowflake_token is not set, Terraform will prompt for it.
# Learner-Login.ps1 sets it automatically — you should not need to type it.

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  authenticator     = "PROGRAMMATIC_ACCESS_TOKEN"
  token             = var.snowflake_token
}
