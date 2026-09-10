variable "azure_location" {
  type        = string
  description = "Azure region for Terraform state backend. Use a region available for your subscription; westeurope may refuse new customers."
  default     = "northeurope"
}

variable "project_name" {
  type        = string
  description = "Prefix for Azure resources"
  default     = "data2ai-tf-training"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group"
  default     = "rg-data2ai-tf-state"
}

variable "storage_account_name" {
  type        = string
  description = "Globally unique Storage Account name (must be 3-24 chars, lowercase letters and numbers)"
  default     = "sadata2aitfstatemsn"
}

variable "container_name" {
  type        = string
  description = "Name of the storage container"
  default     = "tfstate"
}

variable "storage_replication_type" {
  type        = string
  description = "Storage account replication type: LRS (training), GRS (production), ZRS (production with zone redundancy)"
  default     = "LRS"
  validation {
    condition     = contains(["LRS", "GRS", "ZRS", "RAGRS"], var.storage_replication_type)
    error_message = "storage_replication_type must be one of: LRS, GRS, ZRS, RAGRS."
  }
}

variable "container_retention_days" {
  type        = number
  description = "Number of days to retain deleted containers (soft delete). Set to 0 to disable."
  default     = 30
}

variable "blob_retention_days" {
  type        = number
  description = "Number of days to retain deleted blobs (soft delete). Set to 0 to disable."
  default     = 30
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "Resource ID of the Log Analytics Workspace for diagnostic settings. Required for production."
  default     = null
}

variable "state_blob_contributor_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs of principals that need Storage Blob Data Contributor access (CI service connections, deployment identities)."
  default     = []
}

variable "key_vault_name" {
  type        = string
  description = "Name of the Azure Key Vault for storing all secrets (Snowflake, ARM credentials)"
  default     = "kvdata2aitfsecretsmsn"
}

variable "key_vault_sku" {
  type        = string
  description = "Key Vault SKU: standard or premium"
  default     = "standard"

  validation {
    condition     = contains(["standard", "premium"], var.key_vault_sku)
    error_message = "key_vault_sku must be 'standard' or 'premium'."
  }
}

variable "snowflake_organization" {
  type        = string
  description = "Snowflake organization name (stored in Key Vault)"
  default     = ""
}

variable "snowflake_account" {
  type        = string
  description = "Snowflake account identifier (stored in Key Vault)"
  default     = ""
}

variable "snowflake_user" {
  type        = string
  description = "Snowflake service user (stored in Key Vault)"
  default     = ""
}

variable "snowflake_role" {
  type        = string
  description = "Snowflake role (stored in Key Vault)"
  default     = "ACCOUNTADMIN"
}

variable "snowflake_pat" {
  type        = string
  description = "Snowflake PAT for the shared training user (stored in Key Vault as SnowflakePAT). Per-learner PATs are stored as SnowflakePAT-APP01, SnowflakePAT-APP02, etc."
  sensitive   = true
  default     = ""
}

variable "snowflake_learner_prefixes" {
  type        = list(string)
  description = "List of learner prefixes (e.g. APP01, APP02) for per-learner PAT secrets in Key Vault. The instructor sets each secret manually via az keyvault secret set."
  default     = []
}

variable "arm_client_id" {
  type        = string
  description = "Azure Service Principal client ID for backend access (stored in Key Vault)"
  default     = ""
}

variable "arm_client_secret" {
  type        = string
  description = "Azure Service Principal client secret (stored in Key Vault)"
  sensitive   = true
  default     = ""
}

variable "arm_tenant_id" {
  type        = string
  description = "Azure tenant ID (stored in Key Vault)"
  default     = ""
}

variable "arm_subscription_id" {
  type        = string
  description = "Azure subscription ID (stored in Key Vault)"
  default     = ""
}
variable "wif_service_principal_object_id" {
  type        = string
  description = "Object ID of the Workload Identity Federation service principal used by CI pipelines."
  default     = ""
}
