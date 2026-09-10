# Data Mesh Domain Spokes (Test environment)
# See dev/data-mesh-spokes.tf for full documentation.
# This file mirrors the dev spoke model for the test environment.

locals {
  spoke_schemas = flatten([
    for spoke_key, spoke in var.data_mesh_spokes : [
      for zone in spoke.data_zones : [
        for schema in spoke.schemas : {
          spoke_key = spoke_key
          team      = spoke.team
          domain    = spoke.domain
          zone      = zone
          schema    = schema
          db_name   = "DB_${spoke.domain}_${var.environment}"
        }
      ]
    ]
  ])
}

resource "snowflake_database" "spoke" {
  for_each = var.data_mesh_spokes

  name                        = "DB_${each.value.domain}_${var.environment}"
  comment                     = "Data Mesh spoke: ${each.key} | Team: ${each.value.team} | Owner: ${each.value.owner}"
  data_retention_time_in_days = 1

  depends_on = [module.landing_zone]
}

resource "snowflake_schema" "spoke_zone" {
  for_each = {
    for s in local.spoke_schemas : "${s.spoke_key}.${s.zone}" => s
  }

  database = snowflake_database.spoke[each.value.spoke_key].name
  name     = each.value.zone
  comment  = "Data zone ${each.value.zone} for ${each.value.spoke_key} spoke"
}

resource "snowflake_schema" "spoke_business" {
  for_each = {
    for s in local.spoke_schemas : "${s.spoke_key}.${s.zone}.${s.schema}" => s
  }

  database = snowflake_database.spoke[each.value.spoke_key].name
  name     = "${each.value.zone}_${each.value.schema}"
  comment  = "Business schema ${each.value.schema} in ${each.value.zone} for ${each.value.spoke_key}"
}

resource "snowflake_warehouse" "spoke" {
  for_each = var.data_mesh_spokes

  name                = "WH_${var.environment}_${each.value.team}"
  comment             = "Warehouse for ${each.key} spoke | Team: ${each.value.team}"
  warehouse_size      = each.value.warehouse.size
  auto_suspend        = each.value.warehouse.auto_suspend
  auto_resume         = true
  initially_suspended = true
  max_cluster_count   = each.value.warehouse.max_clusters
  min_cluster_count   = 1
  scaling_policy      = "STANDARD"

  resource_monitor = snowflake_resource_monitor.spoke[each.key].name

  depends_on = [module.landing_zone]
}

resource "snowflake_resource_monitor" "spoke" {
  for_each = var.data_mesh_spokes

  name         = "RM_${var.environment}_${each.value.team}"
  credit_quota = each.value.credit_quota
  frequency    = "MONTHLY"

  start_timestamp = "IMMEDIATELY"

  notify_triggers           = [75, 90]
  suspend_trigger           = 100
  suspend_immediate_trigger = 110

  depends_on = [module.landing_zone]
}

resource "snowflake_tag_association" "spoke_db_env" {
  for_each = var.data_mesh_spokes

  object_identifiers = [snowflake_database.spoke[each.key].name]
  object_type        = "DATABASE"
  tag_id             = "${module.landing_zone.raw_database_name}.INGESTION.${module.landing_zone.tag_names.environment}"
  tag_value          = var.environment
}

resource "snowflake_tag_association" "spoke_db_team" {
  for_each = var.data_mesh_spokes

  object_identifiers = [snowflake_database.spoke[each.key].name]
  object_type        = "DATABASE"
  tag_id             = "${module.landing_zone.raw_database_name}.INGESTION.${module.landing_zone.tag_names.team}"
  tag_value          = each.value.team
}

resource "snowflake_tag_association" "spoke_db_owner" {
  for_each = var.data_mesh_spokes

  object_identifiers = [snowflake_database.spoke[each.key].name]
  object_type        = "DATABASE"
  tag_id             = "${module.landing_zone.raw_database_name}.INGESTION.${module.landing_zone.tag_names.owner}"
  tag_value          = each.value.owner
}
