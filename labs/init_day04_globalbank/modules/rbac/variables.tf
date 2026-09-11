# Entrees du module RBAC

variable "prefix" {
  type        = string
  description = "Prefixe de la plateforme"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"
}

variable "roles" {
  type = map(object({
    suffix  = string
    comment = string
  }))
  description = "Roles geres par ce module"
}
