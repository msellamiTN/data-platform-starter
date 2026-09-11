# Contrat expose par le module Landing Zone

output "database_name" {
  value       = snowflake_database.this.name
  description = "Database creee — consommee par Business Data et par les grants"
}

output "schema_name" {
  value = snowflake_schema.this.name
}

output "table_names" {
  value = { for k, v in var.tables : k => snowflake_table.tables[k].name }
}
