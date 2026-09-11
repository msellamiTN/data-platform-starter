# Entrees du module Data Mart

variable "prefix" {
  type        = string
  description = "Prefixe de la plateforme"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"
}

variable "mart" {
  type        = string
  description = "Nom du mart — CUSTOMER, FINANCE ou TRANSACTION"
}

variable "audience" {
  type    = string
  default = "RESEAU"

  validation {
    condition     = contains(["RESEAU", "FINANCE", "RISK", "DIRECTION"], var.audience)
    error_message = "Audience invalide : RESEAU, FINANCE, RISK ou DIRECTION."
  }
}

variable "mart_tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables du data mart"
}
