# ============================================================
# 03-devops-setup — Outputs
# ============================================================

output "project_id" {
  value       = azuredevops_project.training.id
  description = "Azure DevOps project ID."
}

output "project_name" {
  value       = azuredevops_project.training.name
  description = "Azure DevOps project name."
}

output "variable_group_id" {
  value       = azuredevops_variable_group.secrets.id
  description = "Variable group ID (linked to Key Vault)."
}

output "service_endpoint_id" {
  value       = azuredevops_serviceendpoint_azurerm.kv.id
  description = "Service endpoint ID for Azure connection."
}

output "learner_entitlements" {
  value = {
    for k, v in azuredevops_user_entitlement.learners :
    k => v.id
  }
  description = "Map of learner UPN to ADO entitlement ID."
}

output "wif_issuer" {
  value       = azuredevops_serviceendpoint_azurerm.kv.workload_identity_federation_issuer
  description = "WIF issuer URL (for federated identity credential configuration)."
}

output "wif_subject" {
  value       = azuredevops_serviceendpoint_azurerm.kv.workload_identity_federation_subject
  description = "WIF subject (for federated identity credential configuration)."
}
