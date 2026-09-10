output "database_names" {
  value = module.landing_zone.database_names
}

output "role_names" {
  value = module.rbac.role_names
}

output "ingestion_objects" {
  value = {
    stage       = snowflake_stage_internal.internal_raw.name
    file_format = snowflake_file_format.csv_raw.name
  }
}

output "sensitive_check" {
  value     = var.private_key_path
  sensitive = true
}
