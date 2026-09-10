resource "snowflake_user" "terraform_svc" {
  name                           = "TERRAFORM_SVC"
  login_name                     = "TERRAFORM_SVC"
  display_name                   = "TERRAFORM_SVC"
  default_role                   = "ACCOUNTADMIN"
  default_secondary_roles_option = "ALL"
  disabled                       = false
  must_change_password           = false
  rsa_public_key                 = replace(replace(file("${path.module}/../../secrets/snowflake_key.p8"), "-----BEGIN PRIVATE KEY-----", ""), "-----END PRIVATE KEY-----", "")
}
