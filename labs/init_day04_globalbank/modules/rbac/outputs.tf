# Contrat expose par le module RBAC

output "role_names" {
  value       = { for k, v in var.roles : k => snowflake_account_role.access_roles[k].name }
  description = "Noms reels des roles crees"
}
