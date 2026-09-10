resource "tls_private_key" "snowflake_key" {
  algorithm = "RSA"
  rsa_bits  = 2048

  lifecycle {
    prevent_destroy = true
  }
}
