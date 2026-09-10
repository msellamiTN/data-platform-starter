locals {
  pat_file        = "${path.module}/../../secrets/snowflake_pat.txt"
  snowflake_token = try(trimspace(file(local.pat_file)), var.snowflake_token, "")
}

provider "snowflake" {
  organization_name = var.snowflake_organization
  account_name      = var.snowflake_account
  user              = var.snowflake_user
  role              = var.snowflake_role

  authenticator = "PROGRAMMATIC_ACCESS_TOKEN"
  token         = local.snowflake_token

  preview_features_enabled = ["snowflake_table_resource"]
}
