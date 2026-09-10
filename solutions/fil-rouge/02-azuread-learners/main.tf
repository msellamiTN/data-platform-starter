# ============================================================
# 02-azuread-learners — Main
# ============================================================
# Creates Azure AD (Entra ID) users for each learner, adds them
# to a security group, and optionally assigns RBAC role to the group.
#
# API permissions required for the instructor SP:
#   User.ReadWrite.All  OR  Directory.ReadWrite.All
# ============================================================

provider "azuread" {}

provider "azurerm" {
  subscription_id = var.subscription_id
  features {}
}

# ============================================================
# Locals — generate learner maps
# ============================================================

locals {
  learners = {
    for i in range(1, var.learner_count + 1) :
    format("APP%02d", i) => {
      index        = i
      username     = replace(var.username_pattern, "{i}", format("%02d", i))
      display_name = replace(var.display_name_pattern, "{i}", format("%02d", i))
      upn          = "${replace(var.username_pattern, "{i}", format("%02d", i))}@${var.domain}"
      password     = replace(var.password_pattern, "{i}", format("%02d", i))
    }
  }
}

# ============================================================
# Azure AD users
# ============================================================

resource "azuread_user" "learners" {
  for_each = local.learners

  display_name          = each.value.display_name
  user_principal_name   = each.value.upn
  password              = each.value.password
  force_password_change = var.force_password_change
  account_enabled       = true
}

# ============================================================
# Azure AD security group for all learners
# ============================================================

data "azuread_client_config" "current" {}

resource "azuread_group" "learners" {
  display_name     = var.group_name
  security_enabled = true
  owners           = [data.azuread_client_config.current.object_id]
  members          = [for u in azuread_user.learners : u.object_id]
}

# ============================================================
# RBAC role assignment on subscription (optional)
# ============================================================

resource "azurerm_role_assignment" "learner_group" {
  count                = var.assign_rbac ? 1 : 0
  scope                = "/subscriptions/${var.subscription_id}"
  role_definition_name = var.rbac_role
  principal_id         = azuread_group.learners.object_id
}

# ============================================================
# Key Vault access for learners (KV-first auth model)
# Allows learners to fetch SP credentials + PAT from Key Vault
# without manual secret distribution.
# ============================================================

resource "azurerm_role_assignment" "learner_group_kv" {
  count                = (var.grant_kv_access && var.key_vault_id != "") ? 1 : 0
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azuread_group.learners.object_id
}
