data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "kv" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.resource_group_location
  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "KeyVault"
  }
}

data "azurerm_resource_group" "kv" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

locals {
  rg_name     = var.create_resource_group ? azurerm_resource_group.kv[0].name : data.azurerm_resource_group.kv[0].name
  rg_location = var.create_resource_group ? azurerm_resource_group.kv[0].location : data.azurerm_resource_group.kv[0].location
}

resource "azurerm_key_vault" "kv" {
  name                       = var.key_vault_name
  location                   = local.rg_location
  resource_group_name        = local.rg_name
  tenant_id                  = var.tenant_id
  sku_name                   = "standard"
  soft_delete_retention_days = var.soft_delete_retention_days
  purge_protection_enabled   = var.purge_protection_enabled
  enable_rbac_authorization  = true

  tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "Terraform"
    Purpose     = "KeyVault"
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "secrets_user" {
  for_each             = toset(var.rbac_object_ids)
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = each.value
}

resource "azurerm_monitor_diagnostic_setting" "kv" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "kv-diagnostics"
  target_resource_id         = azurerm_key_vault.kv.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "AuditEvent"
  }

  enabled_log {
    category = "AzurePolicyEvaluationDetails"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

# --- Active RSA key ---

resource "tls_private_key" "active" {
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}

resource "azurerm_key_vault_secret" "active_private_key" {
  name         = "snowflake-${var.snowflake_user_name}-${var.key_version}-private-key"
  value        = tls_private_key.active.private_key_pem_pkcs8
  key_vault_id = azurerm_key_vault.kv.id
  tags = {
    Environment = var.environment
    KeyVersion  = var.key_version
    Status      = "active"
    CreatedBy   = "Terraform"
  }

  depends_on = [azurerm_role_assignment.secrets_user]
}

resource "snowflake_user" "svc_user" {
  name           = var.snowflake_user_name
  rsa_public_key = replace(replace(replace(tls_private_key.active.public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", "")
}

# --- Next RSA key for rotation (optional) ---

resource "tls_private_key" "next" {
  count     = var.enable_key_rotation ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = var.rsa_bits
}

resource "azurerm_key_vault_secret" "next_private_key" {
  count        = var.enable_key_rotation ? 1 : 0
  name         = "snowflake-${var.snowflake_user_name}-${var.key_version}-next-private-key"
  value        = tls_private_key.next[0].private_key_pem_pkcs8
  key_vault_id = azurerm_key_vault.kv.id
  tags = {
    Environment = var.environment
    KeyVersion  = var.key_version
    Status      = "next"
    CreatedBy   = "Terraform"
  }

  depends_on = [azurerm_role_assignment.secrets_user]
}
