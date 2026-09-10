output "raw_database_name" {
  value = snowflake_database.raw.name
}

output "curated_database_name" {
  value = snowflake_database.curated.name
}

output "database_names" {
  value = {
    raw     = snowflake_database.raw.name
    curated = snowflake_database.curated.name
  }
}

output "warehouse_names" {
  value = { for k, wh in snowflake_warehouse.this : k => wh.name }
}

output "schema_names" {
  value = [for s in snowflake_schema.business : s.name]
}

# output "resource_monitor_name" {
#   value = snowflake_resource_monitor.this.name
# }

output "schema_map" {
  value = merge(
    { ingestion = snowflake_schema.ingestion.name },
    { for k, s in snowflake_schema.business : k => s.name }
  )
}

output "schemas_by_database" {
  value = {
    raw = concat(
      [snowflake_schema.ingestion.name],
      [for s in snowflake_schema.business : s.name]
    )
  }
}

output "tag_names" {
  value = {
    cost_center = snowflake_tag.cost_center.name
    environment = snowflake_tag.environment.name
    team        = snowflake_tag.team.name
    owner       = snowflake_tag.owner.name
  }
}
