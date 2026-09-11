# Contrat d'entree du module

variable "prefix" {
  type        = string
  description = "Prefixe des objets GlobalBank"
}

variable "environment" {
  type        = string
  description = "Environnement cible — dev ou uat"

  validation {
    condition     = contains(["DEV", "UAT", "PROD"], var.environment)
    error_message = "environment must be DEV, UAT or PROD."
  }
}

variable "owner" {
  type        = string
  description = "Equipe proprietaire du module (platform | data-engineering | business-data | bi-analytics)"
}

variable "common_comment" {
  type        = string
  default     = "Managed by Terraform | GlobalBank"
  description = "Commentaire commun aux ressources"
}
