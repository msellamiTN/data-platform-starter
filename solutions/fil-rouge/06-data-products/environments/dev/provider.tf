provider "snowflake" {
  alias             = "sysadmin"
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = "SYSADMIN"
  password          = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator     = var.deployment_mode == "training" ? "snowflake" : null
  private_key       = var.deployment_mode == "production" ? file(var.private_key_path) : null

  preview_features_enabled = ["snowflake_stage_internal_resource"]
}

provider "snowflake" {
  alias             = "securityadmin"
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = "SECURITYADMIN"
  password          = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator     = var.deployment_mode == "training" ? "snowflake" : null
  private_key       = var.deployment_mode == "production" ? file(var.private_key_path) : null
}
