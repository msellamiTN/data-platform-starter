output "database_names" {
  value = module.landing_zone.database_names
}

output "warehouse_names" {
  value = module.landing_zone.warehouse_names
}

output "schema_names" {
  value = module.landing_zone.schema_names
}

output "schema_map" {
  value = module.landing_zone.schema_map
}

output "schemas_by_database" {
  value = module.landing_zone.schemas_by_database
}
