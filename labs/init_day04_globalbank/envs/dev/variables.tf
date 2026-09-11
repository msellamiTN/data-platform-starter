# Entrees de l'environnement DEV

variable "snowflake_organization" {
  type        = string
  description = "Organisation Snowflake"
}

variable "snowflake_account" {
  type        = string
  description = "Compte Snowflake"
}

variable "snowflake_user" {
  type        = string
  description = "Utilisateur Snowflake"
}

variable "snowflake_token" {
  type        = string
  description = "PAT — lu depuis secrets/, ne rien mettre ici"
  sensitive   = true
  default     = ""
}

variable "prefix" {
  type        = string
  description = "Prefixe des objets GlobalBank"
  default     = "GB"
}

variable "environment" {
  type        = string
  description = "Environnement de deploiement"
  default     = "DEV"

  validation {
    condition     = contains(["DEV", "UAT", "PROD"], var.environment)
    error_message = "environment must be DEV, UAT or PROD."
  }
}

variable "roles" {
  type = map(object({
    suffix  = string
    comment = string
  }))
  description = "Roles a creer"
}

variable "warehouses" {
  type = map(object({
    suffix       = string
    comment      = string
    auto_suspend = number
  }))
  description = "Warehouses a creer"
}

variable "raw_tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables de la landing zone RAW"
}

variable "domain_tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables du data domain"
}

variable "mart_tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables du data mart"
}
