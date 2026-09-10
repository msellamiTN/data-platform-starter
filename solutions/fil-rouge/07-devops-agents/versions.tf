terraform {
  required_version = "= 1.14.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.59.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "= 1.14.0"
    }
  }
}
