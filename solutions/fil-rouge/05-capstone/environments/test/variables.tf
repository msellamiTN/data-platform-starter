variable "snowflake_organization" {
  type        = string
  description = "Snowflake organization name"
}
variable "snowflake_account" {
  type        = string
  description = "Snowflake account name (not locator)"
}
variable "snowflake_user" {
  type        = string
  description = "Service user for Terraform"
  default     = "TERRAFORM_SVC"
}
variable "snowflake_role" {
  type        = string
  description = "Role used by Terraform provider"
  default     = "ACCOUNTADMIN"
}
variable "deployment_mode" {
  type        = string
  description = "Authentication mode: training (password fallback) or production (JWT key-pair)."
  default     = "training"

  validation {
    condition     = contains(["training", "production"], var.deployment_mode)
    error_message = "deployment_mode must be 'training' or 'production'."
  }
}
variable "private_key_path" {
  type        = string
  description = "Path to PKCS#8 private key for Snowflake JWT auth"
  sensitive   = true
  default     = ""
}

variable "snowflake_password" {
  type        = string
  description = "Snowflake password (used when deployment_mode=training)"
  sensitive   = true
  default     = ""
}
variable "environment" {
  type        = string
  description = "Environment suffix (DEV, TEST, PROD)"
  default     = "TEST"
}
variable "project" {
  type        = string
  description = "Project prefix for naming resources"
  default     = "DATAPLATFORM"
}
variable "schemas" {
  type        = set(string)
  description = "Business schemas to create in RAW database"
  default     = ["SALES", "FINANCE", "MARKETING"]
}

variable "credit_quota" {
  type        = number
  description = "Monthly credit quota for Test Resource Monitor"
  default     = 200
}

variable "allowed_ips" {
  type        = list(string)
  description = "List of allowed IP addresses for Network Policy"
  default     = ["0.0.0.0/0"]
}

variable "key_vault_rbac_object_ids" {
  type        = list(string)
  description = "Azure AD object IDs granted Key Vault Secrets User role. Required when key-vault-rsa module is enabled."
  default     = []
}

variable "data_mesh_spokes" {
  type = map(object({
    team       = string
    domain     = string
    data_zones = list(string)
    schemas    = list(string)
    warehouse = object({
      size         = string
      auto_suspend = optional(number, 60)
      max_clusters = optional(number, 1)
    })
    credit_quota = optional(number, 100)
    owner        = string
  }))
  description = "Data Mesh domain spokes. Each spoke declares team, domain, data zones, schemas, warehouse, credit quota, and owner."
  default     = {}
}

variable "arm_subscription_id" {
  type        = string
  description = "Azure subscription ID for the azurerm provider"
  default     = ""
}
