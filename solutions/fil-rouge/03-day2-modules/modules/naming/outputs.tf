output "env_team_role" {
  description = "Canonical ENV_TEAM_ROLE identifier."
  value       = local.env_team_role
}

output "warehouse" {
  description = "Warehouse name following WH_${ENV}_${TEAM}_${WORKLOAD} pattern."
  value       = local.warehouse
}

output "role_business" {
  description = "Business role name following RL_${ENV}_${TEAM}_${ROLE} pattern."
  value       = local.role_business
}

output "role_technical" {
  description = "Technical role name following RL_${ENV}_${TEAM}_${ROLE}_TECH pattern."
  value       = local.role_technical
}

output "service_user" {
  description = "Service user name following SVC_${ENV}_${TEAM}_${ROLE} pattern."
  value       = local.service_user
}

output "storage_integration" {
  description = "Storage integration name following STG_${ENV}_${TEAM}_${DOMAIN} pattern."
  value       = local.storage_integration
}

output "stage" {
  description = "Stage name following STG_${ENV}_${TEAM}_${DOMAIN}_${FORMAT} pattern."
  value       = local.stage
}

output "resource_monitor" {
  description = "Resource monitor name following RM_${ENV}_${TEAM}_${WORKLOAD} pattern."
  value       = local.resource_monitor
}

output "network_policy" {
  description = "Network policy name following NP_${ENV}_${TEAM} pattern."
  value       = local.network_policy
}

output "tag" {
  description = "Tag name following TAG_${DOMAIN}_${CLASSIFICATION} pattern."
  value       = local.tag
}

output "database" {
  description = "Database name following DB_${DOMAIN}_${ENV} pattern (business naming, preserved)."
  value       = local.database
}

output "schema" {
  description = "Schema name following ${DOMAIN}_${WORKLOAD} pattern (business naming, preserved)."
  value       = local.schema
}

output "azure_resource_group" {
  description = "Azure resource group name (lowercase with hyphens)."
  value       = local.azure_resource_group
}

output "azure_storage_account" {
  description = "Azure storage account name (lowercase, no hyphens, max 24 chars)."
  value       = local.azure_storage_account
}

output "azure_key_vault" {
  description = "Azure Key Vault name (lowercase with hyphens)."
  value       = local.azure_key_vault
}

output "azure_container" {
  description = "Azure storage container name for Terraform state."
  value       = local.azure_container
}
