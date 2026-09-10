provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = var.snowflake_role

  # Training mode: password fallback
  password      = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator = var.deployment_mode == "training" ? "snowflake" : null

  # Production mode: JWT key-pair auth
  private_key = var.deployment_mode == "production" ? file(var.private_key_path) : null

  preview_features_enabled = ["snowflake_file_format_resource", "snowflake_stage_internal_resource"]
}

