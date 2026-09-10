# ============================================================
# 03-devops-setup — Main
# ============================================================
# Creates Azure DevOps project, assigns learner entitlements,
# adds them to Contributors group, creates a service connection
# to Azure, and links a variable group to Key Vault.
#
# Prerequisites:
#   - Instructor must be authenticated to ADO (az login + az devops configure)
#   - 02-azuread-learners must be applied first (provides learner UPNs)
#   - 00-bootstrap must be applied first (provides Key Vault)
# ============================================================

provider "azuredevops" {
  org_service_url       = var.ado_organization_url
  personal_access_token = var.ado_pat
}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# ============================================================
# Azure DevOps project
# ============================================================

resource "azuredevops_project" "training" {
  name               = var.project_name
  description        = var.project_description
  visibility         = var.project_visibility
  version_control    = "Git"
  work_item_template = "Agile"
}

# ============================================================
# User entitlements — assign each learner to ADO
# ============================================================

resource "azuredevops_user_entitlement" "learners" {
  for_each             = toset(var.learner_upns)
  principal_name       = each.value
  account_license_type = var.license_type
}

# ============================================================
# Add all learners to the Contributors group
# ============================================================

data "azuredevops_group" "contributors" {
  project_id = azuredevops_project.training.id
  name       = var.group_name
}

resource "azuredevops_group_membership" "learners" {
  group   = data.azuredevops_group.contributors.descriptor
  members = [for u in azuredevops_user_entitlement.learners : u.descriptor]
  mode    = "add"
}

# ============================================================
# Service connection to Azure (for Key Vault access)
# ============================================================

resource "azuredevops_serviceendpoint_azurerm" "kv" {
  project_id                             = azuredevops_project.training.id
  service_endpoint_name                  = var.service_endpoint_name
  description                            = "Service connection for Key Vault variable group"
  service_endpoint_authentication_scheme = var.auth_scheme

  azurerm_spn_tenantid      = var.tenant_id
  azurerm_subscription_id   = var.subscription_id
  azurerm_subscription_name = var.subscription_name
}

# ============================================================
# Variable group linked to Key Vault
# ============================================================

resource "azuredevops_variable_group" "secrets" {
  project_id   = azuredevops_project.training.id
  name         = var.variable_group_name
  description  = "Secrets linked from Azure Key Vault (kvdata2aitfsecrets)"
  allow_access = true

  key_vault {
    name                = var.key_vault_name
    service_endpoint_id = azuredevops_serviceendpoint_azurerm.kv.id
  }

  dynamic "variable" {
    for_each = toset(var.kv_secret_variables)
    content {
      name = variable.value
    }
  }
}
