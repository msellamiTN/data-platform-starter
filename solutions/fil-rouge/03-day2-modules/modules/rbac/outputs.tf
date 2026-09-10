output "role_names" {
  description = "Map of all created role names (key => full ENV_TEAM_ROLE name)"
  value       = local.role_names
}

output "business_role_names" {
  description = "Map of business role names only"
  value = {
    for key, def in var.role_definitions : key => local.role_names[key]
    if def.business
  }
}

output "technical_role_names" {
  description = "Map of technical role names only"
  value = {
    for key, def in var.role_definitions : key => local.role_names[key]
    if !def.business
  }
}
