output "raw_database_name" {
  value       = snowflake_database.raw.name
  description = "Raw layer database name"
}

output "etl_warehouse_name" {
  value       = snowflake_warehouse.etl.name
  description = "ETL warehouse name"
}

output "schema_names" {
  value       = [for s in snowflake_schema.raw : s.name]
  description = "List of created schema names"
}
