# Quelle version de Terraform et quel provider on utilise.
# Les "=" figent les versions : tout le monde a exactement le meme moteur.
terraform {
  required_version = "= 1.14.5"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "= 2.14.0"
    }
  }
}
