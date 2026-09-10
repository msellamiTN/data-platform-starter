terraform {
  required_version = "= 1.14.5"
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "= 2.14.0"
    }
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "= 4.59.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 4.0"
    }
    azuredevops = {
      source  = "microsoft/azuredevops"
      version = "1.14.0"
    }
  }
}
