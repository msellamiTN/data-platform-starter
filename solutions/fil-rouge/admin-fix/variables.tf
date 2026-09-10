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
  description = "Admin user able to manage TERRAFORM_SVC"
  default     = "DATA2AI"
}

variable "snowflake_role" {
  type        = string
  description = "Role used by the admin user"
  default     = "ACCOUNTADMIN"
}

variable "snowflake_password" {
  type        = string
  description = "Password for the admin user"
  sensitive   = true
  default     = ""
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
