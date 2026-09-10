output "platform_summary" {
  description = "Capstone deployment summary"
  value = {
    databases  = module.landing_zone.database_names
    warehouses = module.landing_zone.warehouse_names
    schemas    = module.landing_zone.schema_names
    roles      = module.rbac.role_names
    ingestion = {
      file_format = snowflake_file_format.csv_raw.fully_qualified_name
    }
  }
}
