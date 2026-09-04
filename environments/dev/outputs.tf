output "database_name" {
  description = "Snowflake database name"
  value       = snowflake_database.raw.name
}

output "schema_name" {
  description = "Snowflake schema name"
  value       = snowflake_schema.ingestion.name
}

output "warehouse_name" {
  description = "Snowflake warehouse name"
  value       = snowflake_warehouse.etl.name
}

output "resource_summary" {
  description = "Summary of all created resources"
  value = {
    database  = snowflake_database.raw.name
    schema    = snowflake_schema.ingestion.name
    warehouse = snowflake_warehouse.etl.name
  }
}
