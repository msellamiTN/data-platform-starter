# ============================================================
# 02-azuread-learners — Outputs
# ============================================================

output "learner_upns" {
  value = {
    for k, v in azuread_user.learners :
    k => v.user_principal_name
  }
  description = "Map of learner prefix to Azure AD UPN. Used by 03-devops-setup."
}

output "learner_object_ids" {
  value = {
    for k, v in azuread_user.learners :
    k => v.object_id
  }
  description = "Map of learner prefix to Azure AD object ID."
}

output "group_name" {
  value       = azuread_group.learners.display_name
  description = "Name of the learner security group."
}

output "group_object_id" {
  value       = azuread_group.learners.object_id
  description = "Object ID of the learner security group."
}

output "learner_count" {
  value       = length(azuread_user.learners)
  description = "Number of learner users created."
}
