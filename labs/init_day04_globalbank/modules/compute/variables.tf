# Entrees du module Compute

variable "prefix" {
  type        = string
  description = "Prefixe de la plateforme"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"
}

variable "warehouse_size" {
  type    = string
  default = "X-SMALL"

  validation {
    condition     = contains(["X-SMALL", "SMALL"], var.warehouse_size)
    error_message = "Politique FinOps : seules les tailles X-SMALL et SMALL sont autorisees."
  }
}

variable "warehouses" {
  type = map(object({
    suffix       = string
    comment      = string
    auto_suspend = number
  }))
}
