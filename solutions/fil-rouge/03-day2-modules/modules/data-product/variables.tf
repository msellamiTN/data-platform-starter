variable "domain" {
  type        = string
  description = "Business domain owning the data product"

  validation {
    condition     = can(regex("^[A-Z][A-Z0-9_]*$", var.domain))
    error_message = "domain must use uppercase Snowflake naming."
  }
}

variable "environment" {
  type        = string
  description = "Deployment environment"

  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be DEV, TEST, or PROD."
  }
}

variable "owner_team" {
  type        = string
  description = "Team accountable for the product"
}

variable "warehouse_name" {
  type        = string
  description = "Warehouse used to transform and consume the product"
}

variable "data_retention_days" {
  type        = number
  description = "Snowflake Time Travel retention"
  default     = 1

  validation {
    condition     = var.data_retention_days >= 0 && var.data_retention_days <= 90
    error_message = "data_retention_days must be between 0 and 90."
  }
}
