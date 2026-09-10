provider "azurerm" {
  subscription_id = var.arm_subscription_id
  features {}
}

locals {
  # Avoid duplicate Key Vault Secrets User role assignments when the WIF SP
  # and the learner SP are the same principal.
  learner_kv_secret_users = [
    for id in var.state_blob_contributor_object_ids
    : id if id != var.wif_service_principal_object_id
  ]
}

resource "azurerm_resource_group" "state" {
  name     = var.resource_group_name
  location = var.azure_location
  tags = {
    Purpose     = "TerraformState"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "shared"
  }
}

resource "azurerm_storage_account" "state" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.state.name
  location                 = azurerm_resource_group.state.location
  account_tier             = "Standard"
  account_replication_type = var.storage_replication_type
  min_tls_version          = "TLS1_2"

  blob_properties {
    versioning_enabled  = true
    change_feed_enabled = true

    container_delete_retention_policy {
      days = var.container_retention_days
    }

    delete_retention_policy {
      days = var.blob_retention_days
    }
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Purpose     = "TerraformState"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "shared"
  }
}

resource "azurerm_storage_container" "state" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"
}

resource "azurerm_monitor_diagnostic_setting" "state" {
  count                      = var.log_analytics_workspace_id != null ? 1 : 0
  name                       = "tfstate-diagnostics"
  target_resource_id         = azurerm_storage_account.state.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_role_assignment" "state_blob_contributor" {
  count                = length(var.state_blob_contributor_object_ids)
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = var.state_blob_contributor_object_ids[count.index]
}

resource "azurerm_role_assignment" "state_reader" {
  count                = length(var.state_blob_contributor_object_ids)
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Reader"
  principal_id         = var.state_blob_contributor_object_ids[count.index]
}

resource "azurerm_role_assignment" "state_key_operator" {
  count                = length(var.state_blob_contributor_object_ids)
  scope                = azurerm_storage_account.state.id
  role_definition_name = "Storage Account Key Operator Service Role"
  principal_id         = var.state_blob_contributor_object_ids[count.index]
}

# â”€â”€â”€ Key Vault for all secrets â”€â”€â”€

resource "azurerm_key_vault" "secrets" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.state.location
  resource_group_name        = azurerm_resource_group.state.name
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = var.key_vault_sku
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7

  tags = {
    Purpose     = "TerraformSecrets"
    ManagedBy   = "Terraform"
    Project     = var.project_name
    Environment = "shared"
  }
}

data "azurerm_client_config" "current" {}

# Grant Key Vault Administrator to the deployer identity
resource "azurerm_role_assignment" "kv_admin" {
  scope                = azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Administrator"
  principal_id         = data.azurerm_client_config.current.object_id
}

# â”€â”€â”€ Snowflake secrets â”€â”€â”€

resource "azurerm_key_vault_secret" "snowflake_organization" {
  name         = "SnowflakeOrganization"
  value        = var.snowflake_organization
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "snowflake_account" {
  name         = "SnowflakeAccount"
  value        = var.snowflake_account
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "snowflake_user" {
  name         = "SnowflakeUser"
  value        = var.snowflake_user
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "snowflake_role" {
  name         = "SnowflakeRole"
  value        = var.snowflake_role
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "snowflake_pat" {
  name         = "SnowflakePAT"
  value        = var.snowflake_pat
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

# Per-learner PAT secrets are created manually by the instructor:
#   az keyvault secret set --vault-name kvdata2aitfsecrets \
#     --name SnowflakePAT-APP01 --value "<PAT>"
#
# This avoids storing all PATs in Terraform state.
# The snowflake_learner_prefixes variable is used only for documentation
# and to trigger a reminder output.

# â”€â”€â”€ ARM credentials secrets â”€â”€â”€

resource "azurerm_key_vault_secret" "arm_client_id" {
  name         = "ArmClientId"
  value        = var.arm_client_id
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "arm_client_secret" {
  name         = "ArmClientSecret"
  value        = var.arm_client_secret
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "arm_tenant_id" {
  name         = "ArmTenantId"
  value        = var.arm_tenant_id
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

resource "azurerm_key_vault_secret" "arm_subscription_id" {
  name         = "ArmSubscriptionId"
  value        = var.arm_subscription_id
  key_vault_id = azurerm_key_vault.secrets.id
  depends_on   = [azurerm_role_assignment.kv_admin]
}

# Grant Key Vault Secrets User to the WIF CI service principal
resource "azurerm_role_assignment" "kv_secrets_user" {
  count                = var.wif_service_principal_object_id != "" ? 1 : 0
  scope                = azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = var.wif_service_principal_object_id
  depends_on           = [azurerm_role_assignment.kv_admin]
}

# Grant Key Vault Secrets User to the shared learner service principal
# so that Learner-Login.ps1 can retrieve the PAT at runtime.
# The object ID is the same SP that has Storage Blob Data Contributor above.
resource "azurerm_role_assignment" "kv_secrets_user_learner" {
  count                = length(local.learner_kv_secret_users)
  scope                = azurerm_key_vault.secrets.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = local.learner_kv_secret_users[count.index]
  depends_on           = [azurerm_role_assignment.kv_admin]
}
