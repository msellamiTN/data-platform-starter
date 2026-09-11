# Contrat expose par le module Data Mart

output "database_name" {
  value       = snowflake_database.this.name
  description = "Data mart — consomme par Power BI"
}

output "mart_contract" {
  value = {
    database    = snowflake_database.this.name
    schema      = snowflake_schema.this.name
    mart        = lower(var.mart)
    audience    = var.audience
    environment = var.environment
  }
  description = "Contrat du data mart — pilote les grants"
}
