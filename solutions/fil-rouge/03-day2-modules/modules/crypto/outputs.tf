output "private_key_pem" {
  value     = tls_private_key.snowflake_key.private_key_pem
  sensitive = true
}

output "private_key_pkcs8" {
  value     = tls_private_key.snowflake_key.private_key_pem_pkcs8
  sensitive = true
}

output "public_key_pem" {
  value = tls_private_key.snowflake_key.public_key_pem
}

output "public_key_nocrypt" {
  # Strip headers and newlines for Snowflake compatibility
  value = replace(
    replace(
      replace(tls_private_key.snowflake_key.public_key_pem, "-----BEGIN PUBLIC KEY-----", ""),
      "-----END PUBLIC KEY-----",
      ""
    ),
    "/[\r\n]+/",
    ""
  )
}
