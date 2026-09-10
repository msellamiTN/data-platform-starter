terraform {
  required_version = "= 1.14.5"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = "= 3.1.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.59.0"
    }
  }
}
