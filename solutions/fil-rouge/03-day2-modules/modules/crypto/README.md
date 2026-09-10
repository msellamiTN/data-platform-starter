# Module: crypto

Generates RSA key pairs for Snowflake key-pair authentication (JWT).

## Risk Note

> **Warning:** The `tls_private_key` resource stores the private key in Terraform state. This module is retained **only for teaching and sandbox demonstration**. For production, use the `key-vault-rsa` module which stores private keys in Azure Key Vault and never exposes them in outputs.

## Purpose

This module generates a 2048-bit RSA private key using the Terraform `tls` provider. The private key is stored in Azure Key Vault by the calling environment, and the public key is assigned to a Snowflake service user.

## Usage

```hcl
module "crypto" {
  source = "../../modules/crypto"
}

# Store private key in Key Vault
resource "azurerm_key_vault_secret" "snowflake_private_key" {
  name         = "snowflake-private-key"
  value        = module.crypto.private_key_pem
  key_vault_id = azurerm_key_vault.kv.id
}

# Assign public key to Snowflake user
resource "snowflake_user" "svc_user" {
  name           = "SVC_DEV_USER"
  rsa_public_key = module.crypto.public_key_nocrypt
}
```

## Inputs

No inputs — this module takes no variables.

## Outputs

| Name | Description | Sensitive |
|------|-------------|-----------|
| `private_key_pem` | PEM-encoded RSA private key | Yes |
| `public_key_pem` | PEM-encoded RSA public key (with headers) | No |
| `public_key_nocrypt` | RSA public key without headers/newlines (Snowflake-compatible) | No |
