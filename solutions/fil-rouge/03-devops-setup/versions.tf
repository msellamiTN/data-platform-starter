terraform {
  required_version = "= 1.14.5"

  required_providers {
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "= 1.14.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.59.0"
    }
  }
}
