/*
 * Azure Key Vault and production RSA key management (opt-in).
 * Uncomment when deployment_mode = "production" and Azure subscription is available.
 * The key-vault-rsa module creates the Key Vault, generates RSA keys, stores
 * the private key in Key Vault, and registers the public key with Snowflake.
 *
 * See docs/key-rotation-runbook.md for the rotation procedure.
 */

/*
data "azurerm_client_config" "current" {}

module "key_vault_rsa" {
  source = "../../../03-day2-modules/modules/key-vault-rsa"

  resource_group_name   = "rg-${lower(var.project)}-${lower(var.environment)}"
  key_vault_name        = "kv-${lower(var.project)}-${lower(var.environment)}"
  tenant_id             = data.azurerm_client_config.current.tenant_id
  environment           = var.environment
  project_name          = var.project
  snowflake_user_name   = "SVC_${var.environment}_DATA_ENG"
  key_version           = "v1"
  enable_key_rotation   = true
  rbac_object_ids       = var.key_vault_rbac_object_ids
}
*/

# Crypto module to generate RSA keys (training/sandbox only â€” see risk note in module README)
module "crypto" {
  source = "../../../03-day2-modules/modules/crypto"
}

# Landing Zone (databases, warehouses, monitors, tags)
module "landing_zone" {
  source = "../../../03-day2-modules/modules/landing-zone"

  environment  = var.environment
  project      = var.project
  schemas      = var.schemas
  credit_quota = var.credit_quota

  warehouses = {
    etl = {
      size         = "X-SMALL"
      auto_suspend = 60
      max_clusters = 2
    }
    analytics = {
      size         = "SMALL"
      auto_suspend = 120
    }
  }
}

# RBAC configuration (Technical & Business roles)
module "rbac" {
  source = "../../../03-day2-modules/modules/rbac"

  environment           = var.environment
  raw_database_name     = module.landing_zone.raw_database_name
  curated_database_name = module.landing_zone.curated_database_name
  etl_warehouse_name    = module.landing_zone.warehouse_names["etl"]
}

# Snowflake User authenticated via generated RSA Key
resource "snowflake_user" "svc_user" {
  name              = "SVC_${var.environment}_USER"
  login_name        = "SVC_${var.environment}_USER"
  default_warehouse = module.landing_zone.warehouse_names["etl"]
  default_role      = "RL_DATA_ENGINEER_${var.environment}"
  rsa_public_key    = module.crypto.public_key_nocrypt
}

/*
# Azure Storage Integration for external stage loading
resource "snowflake_storage_integration_azure" "azure_integration" {
  name                      = "SI_AZURE_${var.environment}"
  comment                   = "Storage integration for Azure Blob Storage - ${var.environment}"
  enabled                   = true
  storage_allowed_locations = ["azure://sadata2aitfstate.blob.core.windows.net/tfstate/"]
  azure_tenant_id           = data.azurerm_client_config.current.tenant_id
}
*/

resource "snowflake_file_format" "csv_raw" {
  depends_on = [module.landing_zone]

  name                         = "FF_CSV_RAW"
  database                     = module.landing_zone.raw_database_name
  schema                       = "INGESTION"
  format_type                  = "CSV"
  field_optionally_enclosed_by = "\""
  skip_header                  = 1
}

/*
# External Stage pointing to Azure container
resource "snowflake_stage_external_azure" "azure_raw" {
  name                = "STG_AZURE_RAW"
  database            = module.landing_zone.raw_database_name
  schema              = "INGESTION"
  url                 = "azure://sadata2aitfstate.blob.core.windows.net/tfstate/"
  storage_integration = snowflake_storage_integration_azure.azure_integration.name
}
*/

# Security: Network Policy to restrict connection IPs (Well-Architected Security)
resource "snowflake_network_policy" "dev_policy" {
  name            = "NP_DEV_SECURITY"
  comment         = "Network policy for Dev environment - Well-Architected Security"
  allowed_ip_list = var.allowed_ips
  blocked_ip_list = []
}


