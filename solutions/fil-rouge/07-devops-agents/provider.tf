provider "azurerm" {
  subscription_id = var.arm_subscription_id
  features {}
}

provider "azuredevops" {
  org_service_url       = var.azuredevops_org_url
  personal_access_token = var.azuredevops_pat
}
