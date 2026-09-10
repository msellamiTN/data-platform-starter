# ============================================================
# 03-devops-setup — Variables
# ============================================================

variable "ado_organization_url" {
  type        = string
  description = "Azure DevOps organization URL (e.g. https://dev.azure.com/myorg)."
}

variable "ado_pat" {
  type        = string
  description = "Azure DevOps Personal Access Token (PAT) with full access."
  sensitive   = true
}

variable "project_name" {
  type        = string
  description = "Azure DevOps project name."
  default     = "terraform-snowflake"
}

variable "project_description" {
  type        = string
  description = "Azure DevOps project description."
  default     = "Formation Terraform & Snowflake — Data2AI Academy"
}

variable "project_visibility" {
  type        = string
  description = "Project visibility: private or public."
  default     = "private"
}

variable "learner_upns" {
  type        = list(string)
  description = "List of learner UPNs from 02-azuread-learners output. Used to assign ADO entitlements."
}

variable "license_type" {
  type        = string
  description = "ADO license type for learners: stakeholder, express (basic), or professional."
  default     = "express"
}

variable "group_name" {
  type        = string
  description = "ADO group to add learners to (e.g. Contributors)."
  default     = "Contributors"
}

# ============================================================
# Azure service connection (for variable group → Key Vault)
# ============================================================

variable "key_vault_name" {
  type        = string
  description = "Name of the Azure Key Vault (from 00-bootstrap)."
}

variable "subscription_id" {
  type        = string
  description = "Azure subscription ID for the service connection."
}

variable "subscription_name" {
  type        = string
  description = "Azure subscription display name for the service connection."
  default     = "Data2AI-Training"
}

variable "tenant_id" {
  type        = string
  description = "Azure tenant ID for the service connection."
}

variable "service_endpoint_name" {
  type        = string
  description = "Name of the ADO service endpoint to Azure."
  default     = "AzureKeyVault-Connection"
}

variable "auth_scheme" {
  type        = string
  description = "Authentication scheme: WorkloadIdentityFederation (preferred) or ServicePrincipal."
  default     = "WorkloadIdentityFederation"
}

# ============================================================
# Variable group
# ============================================================

variable "variable_group_name" {
  type        = string
  description = "Name of the ADO variable group linked to Key Vault."
  default     = "data-platform-secrets"
}

variable "kv_secret_variables" {
  type        = list(string)
  description = "List of Key Vault secret names to expose as ADO variables."
  default     = ["SnowflakePAT", "ArmClientSecret"]
}
