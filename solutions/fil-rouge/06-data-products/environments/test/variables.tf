variable "snowflake_organization" {
  type        = string
  description = "Snowflake organization name"
}

variable "snowflake_account" {
  type        = string
  description = "Snowflake account name"
}

variable "snowflake_user" {
  type        = string
  description = "Technical deployment user"
}

variable "snowflake_role" {
  type        = string
  description = "Role used by Terraform provider"
  default     = "ACCOUNTADMIN"
}

variable "snowflake_password" {
  type        = string
  description = "Training-only password supplied outside Git"
  sensitive   = true
  default     = ""
  nullable    = false
}

variable "private_key_path" {
  type        = string
  description = "Production PKCS#8 key path"
  sensitive   = true
  default     = null
  nullable    = true
}

variable "deployment_mode" {
  type        = string
  description = "Authentication mode"
  default     = "training"

  validation {
    condition     = contains(["training", "production"], var.deployment_mode)
    error_message = "deployment_mode must be training or production."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"
  default     = "TEST"

  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be DEV, TEST, or PROD."
  }
}

variable "data_products" {
  type = map(object({
    owner_team          = string
    data_retention_days = optional(number, 1)
  }))
  description = "Domain data products"

  default = {
    SALES = {
      owner_team = "TEAM_SALES"
    }
    FINANCE = {
      owner_team = "TEAM_FINANCE"
    }
  }
}

