variable "environment" {
  type        = string
  description = "Environment suffix"
  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be DEV, TEST, or PROD."
  }
}

variable "project" {
  type    = string
  default = "DATAPLATFORM"
}

variable "schemas" {
  type        = set(string)
  description = "Business schemas to create in the RAW database (in addition to the always-created INGESTION schema)"
  default     = ["RAW", "SILVER", "GOLD"]
}

variable "warehouses" {
  type = map(object({
    size         = string
    auto_suspend = optional(number, 60)
    max_clusters = optional(number, 1)
  }))
  description = "Map of warehouse suffix => config"
  default = {
    etl = {
      size = "X-SMALL"
    }
    analytics = {
      size = "SMALL"
    }
  }
}

variable "data_retention_days" {
  type    = number
  default = 1
}

variable "credit_quota" {
  type        = number
  description = "Monthly credit quota for the resource monitor"
  default     = 100
}

