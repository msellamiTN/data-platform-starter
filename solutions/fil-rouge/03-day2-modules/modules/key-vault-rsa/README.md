# Module: key-vault-rsa

Production-grade Azure Key Vault with RSA key generation for Snowflake JWT authentication. This module replaces the commented-out Key Vault blocks in the capstone and provides a controlled key rotation path.

## Risk Note

The `tls_private_key` resource stores the private key in Terraform state. This module is designed for production by immediately storing the key in Azure Key Vault and never exposing it in outputs. However, the key material does transit through Terraform state.

For maximum security, generate keys outside Terraform (e.g. via Azure CLI or a pipeline step) and upload directly to Key Vault. This module is retained because:
1. It provides a reproducible, auditable key creation path.
2. The private key is never output (only the Key Vault secret reference).
3. State is stored in Azure Blob with encryption and RBAC access control.

## Usage

### Basic (single key)

```hcl
module "key_vault_rsa" {
  source                = "../../../03-day2-modules/modules/key-vault-rsa"
  resource_group_name   = "rg-dataplatform-dev"
  key_vault_name        = "kv-dataplatform-dev"
  tenant_id             = data.azurerm_client_config.current.tenant_id
  environment           = "DEV"
  snowflake_user_name   = "SVC_DEV_DATA_ENG"
  key_version           = "v1"
  rbac_object_ids       = ["<ci-service-connection-object-id>"]
}
```

### With key rotation (two-key cutover)

```hcl
module "key_vault_rsa" {
  source                = "../../../03-day2-modules/modules/key-vault-rsa"
  resource_group_name   = "rg-dataplatform-dev"
  key_vault_name        = "kv-dataplatform-dev"
  tenant_id             = data.azurerm_client_config.current.tenant_id
  environment           = "DEV"
  snowflake_user_name   = "SVC_DEV_DATA_ENG"
  key_version           = "v1"
  enable_key_rotation   = true
  rbac_object_ids       = ["<ci-service-connection-object-id>"]
}
```

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `resource_group_name` | string | yes | | Azure resource group name |
| `resource_group_location` | string | no | `northeurope` | Azure region (use a region available for your subscription) |
| `key_vault_name` | string | yes | | Key Vault name (globally unique) |
| `tenant_id` | string | yes | | Azure AD tenant ID |
| `environment` | string | no | `DEV` | `DEV`, `TEST`, or `PROD` |
| `project_name` | string | no | `terraform-snowflake` | Project tag |
| `create_resource_group` | bool | no | `true` | Create or use existing RG |
| `soft_delete_retention_days` | number | no | `30` | Soft delete retention |
| `purge_protection_enabled` | bool | no | `true` | Purge protection |
| `rbac_object_ids` | list(string) | no | `[]` | Object IDs for Secrets User role |
| `log_analytics_workspace_id` | string | no | `null` | Log Analytics for diagnostics |
| `snowflake_user_name` | string | yes | | Snowflake service user name |
| `key_version` | string | no | `v1` | Key version (e.g. v1, v2) |
| `rsa_bits` | number | no | `2048` | RSA key size |
| `enable_key_rotation` | bool | no | `false` | Generate a second key for rotation |

## Outputs

| Name | Description |
|------|-------------|
| `key_vault_id` | Key Vault resource ID |
| `key_vault_name` | Key Vault name |
| `key_vault_uri` | Key Vault URI |
| `active_secret_id` | Active private key secret ID |
| `active_secret_name` | Active private key secret name |
| `active_public_key_pem` | Active public key (PEM with headers) |
| `active_public_key_clean` | Active public key (Snowflake-compatible) |
| `next_secret_id` | Next key secret ID (if rotation enabled) |
| `next_public_key_pem` | Next public key (if rotation enabled) |
| `snowflake_user_name` | Snowflake user with registered public key |

## Key Rotation Procedure

See `docs/key-rotation-runbook.md` for the complete cutover procedure.
