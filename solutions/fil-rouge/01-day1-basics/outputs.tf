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

output "connection_hint" {
  value       = "USE DATABASE ${snowflake_database.raw.name}; USE WAREHOUSE ${snowflake_warehouse.etl.name};"
  description = "Quick start SQL for Snowflake worksheet"
}

output "environment_summary" {
  value = {
    database    = snowflake_database.raw.name
    warehouse   = snowflake_warehouse.etl.name
    schemas     = [for s in snowflake_schema.raw : s.name]
    environment = var.environment
  }
  description = "Resume structure du deploiement"
}
