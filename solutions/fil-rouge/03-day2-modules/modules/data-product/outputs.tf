output "database_name" {
  description = "Domain database"
  value       = snowflake_database.this.name
}

output "schema_names" {
  description = "Medallion schemas by zone"
  value       = { for zone, schema in snowflake_schema.zone : zone => schema.name }
}

output "stage_name" {
  description = "Internal RAW ingestion stage"
  value       = snowflake_stage_internal.raw.name
}

output "reader_role_name" {
  description = "Consumer role"
  value       = snowflake_account_role.reader.name
}

output "producer_role_name" {
  description = "Producer role"
  value       = snowflake_account_role.producer.name
}
