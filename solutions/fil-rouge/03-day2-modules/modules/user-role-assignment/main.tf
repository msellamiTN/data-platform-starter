resource "snowflake_user" "this" {
  for_each = var.users

  name              = each.key
  login_name        = each.key
  default_warehouse = each.value.default_warehouse
  default_role      = each.value.default_role
  comment           = try(each.value.comment, "Managed by Terraform")
}

resource "snowflake_grant_account_role" "user_roles" {
  for_each = {
    for pair in flatten([
      for user_name, user_config in var.users : [
        for role_name in user_config.roles : {
          user_name = user_name
          role_name = role_name
        }
      ]
    ]) : "${pair.user_name}-${pair.role_name}" => pair
  }

  role_name = each.value.role_name
  user_name = each.value.user_name
}
