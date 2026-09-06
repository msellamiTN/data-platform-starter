# Provider Snowflake
#
# The PAT is read from secrets/snowflake_pat.txt (created by New-SnowflakeConnection.ps1).
# If the file is missing, it falls back to TF_VAR_snowflake_token env var set by Learner-Login.ps1.
#
# No secret is written in .tf files. The token stays in the locals block.

locals {
  pat_file        = "${path.module}/../../secrets/snowflake_pat.txt"
  snowflake_token = try(trim(file(local.pat_file), "\n\r"), var.snowflake_token, "")
}

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  authenticator     = "PROGRAMMATIC_ACCESS_TOKEN"
  token             = local.snowflake_token
}
