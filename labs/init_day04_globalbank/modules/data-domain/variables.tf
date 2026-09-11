# Entrees du module Data Domain

variable "prefix" {
  type        = string
  description = "Prefixe de la plateforme"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"
}

variable "domain" {
  type        = string
  description = "Nom du domaine metier — CUSTOMER, PRODUCT ou CAMPAIGN"
}

variable "classification" {
  type    = string
  default = "INTERNE"

  validation {
    condition     = contains(["PUBLIC", "INTERNE", "CONFIDENTIEL", "SECRET"], var.classification)
    error_message = "Classification invalide : PUBLIC, INTERNE, CONFIDENTIEL ou SECRET."
  }
}

variable "tables" {
  type = map(object({
    name    = string
    comment = string
  }))
  description = "Tables metier du domaine"
}
