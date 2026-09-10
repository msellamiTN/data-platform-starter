variable "environment" {
  description = "Deployment environment. Must be uppercase: DEV, TEST, or PROD."
  type        = string
  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be one of: DEV, TEST, PROD (uppercase)."
  }
}

variable "team" {
  description = "Domain team name in uppercase with underscores (e.g. DATA_ENG, ANALYTICS, GOVERNANCE)."
  type        = string
  validation {
    condition     = can(regex("^[A-Z][A-Z0-9_]*$", var.team))
    error_message = "team must be uppercase alphanumeric with underscores, starting with a letter."
  }
}

variable "role" {
  description = "Functional role in uppercase with underscores (e.g. ENGINEER, ANALYST, STEWARD)."
  type        = string
  default     = ""
  validation {
    condition     = var.role == "" || can(regex("^[A-Z][A-Z0-9_]*$", var.role))
    error_message = "role must be uppercase alphanumeric with underscores, starting with a letter."
  }
}

variable "domain" {
  description = "Data mesh domain in uppercase (e.g. RAW, CURATED, GOLD, SILVER)."
  type        = string
  default     = ""
  validation {
    condition     = var.domain == "" || can(regex("^[A-Z][A-Z0-9_]*$", var.domain))
    error_message = "domain must be uppercase alphanumeric with underscores, starting with a letter."
  }
}

variable "workload" {
  description = "Workload type in uppercase (e.g. ETL, BATCH, SERVING)."
  type        = string
  default     = ""
  validation {
    condition     = var.workload == "" || can(regex("^[A-Z][A-Z0-9_]*$", var.workload))
    error_message = "workload must be uppercase alphanumeric with underscores, starting with a letter."
  }
}

variable "format" {
  description = "File format or data format identifier (e.g. CSV, PARQUET, JSON)."
  type        = string
  default     = ""
  validation {
    condition     = var.format == "" || can(regex("^[A-Z][A-Z0-9_]*$", var.format))
    error_message = "format must be uppercase alphanumeric with underscores, starting with a letter."
  }
}

variable "classification" {
  description = "Data classification tag (e.g. PII, SENSITIVE, PUBLIC)."
  type        = string
  default     = ""
  validation {
    condition     = var.classification == "" || can(regex("^[A-Z][A-Z0-9_]*$", var.classification))
    error_message = "classification must be uppercase alphanumeric with underscores, starting with a letter."
  }
}
