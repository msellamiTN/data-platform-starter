variable "resource_group_name" {
  type        = string
  description = "Name of the Azure resource group for Key Vault. If create_resource_group is true, this name is used to create it."
}

variable "resource_group_location" {
  type        = string
  description = "Azure region for the resource group and Key Vault. Use a region available for your subscription; westeurope may refuse new customers."
  default     = "northeurope"
}

variable "key_vault_name" {
  type        = string
  description = "Name of the Azure Key Vault (must be globally unique, 3-24 chars, lowercase alphanumeric with hyphens)."
}

variable "tenant_id" {
  type        = string
  description = "Azure AD tenant ID for Key Vault access policies."
}

variable "environment" {
  type        = string
  description = "Deployment environment for tagging."
  default     = "DEV"

  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be one of: DEV, TEST, PROD."
  }
}

variable "project_name" {
  type        = string
  description = "Project name for tagging."
  default     = "terraform-snowflake"
}

variable "create_resource_group" {
  type        = bool
  description = "If true, create the resource group. If false, use an existing resource group via data source."
  default     = true
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Number of days to retain soft-deleted Key Vault secrets."
  default     = 30
}

variable "purge_protection_enabled" {
  type        = bool
  description = "Enable purge protection on Key Vault. Cannot be disabled once enabled. Recommended for production."
  default     = true
}

variable "rbac_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs of principals granted Key Vault Secrets User role (CI service connections, deployment identities)."
  default     = []
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace for diagnostic settings. Set to null to disable diagnostics."
  default     = null
}

variable "snowflake_user_name" {
  type        = string
  description = "Name of the Snowflake service user to register the public key with."
}

variable "key_version" {
  type        = string
  description = "Key version identifier (e.g. 'v1', 'v2'). Used in secret naming and rotation tracking."
  default     = "v1"

  validation {
    condition     = can(regex("^v[0-9]+$", var.key_version))
    error_message = "key_version must match pattern v<number> (e.g. v1, v2)."
  }
}

variable "rsa_bits" {
  type        = number
  description = "RSA key size in bits. 2048 is minimum; 4096 recommended for production."
  default     = 2048

  validation {
    condition     = contains([2048, 3072, 4096], var.rsa_bits)
    error_message = "rsa_bits must be 2048, 3072, or 4096."
  }
}

variable "enable_key_rotation" {
  type        = bool
  description = "If true, generate a second key (next_key) for rotation cutover. The active key is registered as rsa_public_key; the next key is stored as a separate secret."
  default     = false
}
