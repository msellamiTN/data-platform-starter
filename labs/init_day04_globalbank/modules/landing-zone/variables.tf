# Entrees du module Landing Zone

variable "prefix" {
  type        = string
  description = "Prefixe de la plateforme"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"
}

variable "zone" {
  type        = string
  description = "Nom de la zone — RAW ou CORE"
}

variable "schema_name" {
  type        = string
  description = "Schema de la zone — LANDING ou DIM"
}

variable "audit_column" {
  type    = string
  default = "LOAD_TS"

  validation {
    condition     = can(regex("_TS$", var.audit_column))
    error_message = "Politique de gouvernance : la colonne d'audit doit se terminer par _TS."
  }
}

variable "tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables de la zone"
}
