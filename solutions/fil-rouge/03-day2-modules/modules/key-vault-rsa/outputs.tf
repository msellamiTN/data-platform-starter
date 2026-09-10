output "key_vault_id" {
  value       = azurerm_key_vault.kv.id
  description = "Resource ID of the Azure Key Vault."
}

output "key_vault_name" {
  value       = azurerm_key_vault.kv.name
  description = "Name of the Azure Key Vault."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.kv.vault_uri
  description = "URI of the Azure Key Vault for secret retrieval at runtime."
}

output "active_secret_id" {
  value       = azurerm_key_vault_secret.active_private_key.id
  description = "Secret ID of the active private key in Key Vault."
}

output "active_secret_name" {
  value       = azurerm_key_vault_secret.active_private_key.name
  description = "Secret name of the active private key in Key Vault."
}

output "active_public_key_pem" {
  value       = tls_private_key.active.public_key_pem
  description = "PEM-encoded active RSA public key (with headers)."
}

output "active_public_key_clean" {
  value       = replace(replace(replace(tls_private_key.active.public_key_pem, "-----BEGIN PUBLIC KEY-----", ""), "-----END PUBLIC KEY-----", ""), "\n", "")
  description = "Active RSA public key without headers/newlines (Snowflake-compatible)."
}

output "next_secret_id" {
  value       = var.enable_key_rotation ? azurerm_key_vault_secret.next_private_key[0].id : null
  description = "Secret ID of the next (rotation) private key in Key Vault, if enabled."
}

output "next_public_key_pem" {
  value       = var.enable_key_rotation ? tls_private_key.next[0].public_key_pem : null
  description = "PEM-encoded next RSA public key, if rotation is enabled."
}

output "snowflake_user_name" {
  value       = snowflake_user.svc_user.name
  description = "Name of the Snowflake service user with the registered public key."
}
