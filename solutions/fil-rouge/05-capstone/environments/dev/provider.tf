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

  preview_features_enabled = ["snowflake_file_format_resource", "snowflake_stage_internal_resource", "snowflake_stage_external_azure_resource"]
}

# Provider alias: SYSADMIN for database/warehouse/schema operations
provider "snowflake" {
  alias             = "sysadmin"
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = "SYSADMIN"

  password      = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator = var.deployment_mode == "training" ? "snowflake" : null
  private_key   = var.deployment_mode == "production" ? file(var.private_key_path) : null

  preview_features_enabled = ["snowflake_file_format_resource", "snowflake_stage_internal_resource", "snowflake_stage_external_azure_resource"]
}

# Provider alias: USERADMIN for user and role management
provider "snowflake" {
  alias             = "useradmin"
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = "USERADMIN"

  password      = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator = var.deployment_mode == "training" ? "snowflake" : null
  private_key   = var.deployment_mode == "production" ? file(var.private_key_path) : null
}

# Provider alias: SECURITYADMIN for RBAC and security operations
provider "snowflake" {
  alias             = "securityadmin"
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = "SECURITYADMIN"

  password      = var.deployment_mode == "training" ? var.snowflake_password : null
  authenticator = var.deployment_mode == "training" ? "snowflake" : null
  private_key   = var.deployment_mode == "production" ? file(var.private_key_path) : null
}

provider "azurerm" {
  features {}
}

