# Contrat expose par le module Data Domain

output "database_name" {
  value       = snowflake_database.this.name
  description = "Database du domaine — consommee par BI"
}

output "domain_contract" {
  value = {
    database       = snowflake_database.this.name
    schema         = snowflake_schema.this.name
    domain         = lower(var.domain)
    classification = var.classification
    environment    = var.environment
  }
  description = "Contrat du data product"
}
