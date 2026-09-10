output "user_names" {
  description = "List of created user names"
  value       = [for u in snowflake_user.this : u.name]
}

output "user_role_assignments" {
  description = "Map of user => roles assigned"
  value = {
    for user_name, user_config in var.users :
    user_name => user_config.roles
  }
}
