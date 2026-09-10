# ============================================================
# 02-azuread-learners — Variables
# ============================================================

variable "learner_count" {
  type        = number
  description = "Number of learner users to create in Azure AD."
  default     = 12
}

variable "domain" {
  type        = string
  description = "Azure AD verified domain for UPNs (e.g. data2ai.onmicrosoft.com)."
}

variable "username_pattern" {
  type        = string
  description = "Pattern for Azure AD usernames. {i} is replaced with the zero-padded index."
  default     = "apprenant{i}"
}

variable "display_name_pattern" {
  type        = string
  description = "Pattern for display names. {i} is replaced with the zero-padded index."
  default     = "Apprenant {i}"
}

variable "password_pattern" {
  type        = string
  description = "Pattern for Azure AD passwords. {i} is replaced with the zero-padded index. Must meet Azure AD password policy."
  sensitive   = true
  default     = "AzureLearner2026@{i}"
}

variable "force_password_change" {
  type        = bool
  description = "Whether learners must change their password on first login."
  default     = true
}

variable "group_name" {
  type        = string
  description = "Name of the Azure AD security group for all learners."
  default     = "Data2AI-Learners"
}

# ============================================================
# Azure RBAC (optional — assign role to the learner group)
# ============================================================

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID for RBAC role assignment."
}

variable "rbac_role" {
  type        = string
  description = "RBAC role to assign to the learner group on the subscription."
  default     = "Reader"
}

variable "assign_rbac" {
  type        = bool
  description = "Whether to assign the RBAC role to the learner group."
  default     = true
}

# ============================================================
# Key Vault access for learners (KV-first auth model)
# ============================================================

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the Key Vault. Learners group will be granted Key Vault Secrets User to fetch SP credentials and PAT."
  default     = ""
}

variable "grant_kv_access" {
  type        = bool
  description = "Whether to grant the learner group Key Vault Secrets User on the Key Vault."
  default     = true
}
