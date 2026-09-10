# Data Mesh Domain Spokes
#
# This file deploys Data Mesh spokes using for_each from the data_mesh_spokes variable.
# Each spoke creates:
#   - A domain-specific database (DB_${DOMAIN}_${ENV})
#   - Data zone schemas (RAW, SILVER, GOLD)
#   - Business schemas within each data zone
#   - A domain-specific warehouse (WH_${ENV}_${TEAM}_${WORKLOAD})
#   - A resource monitor with credit quota
#   - Tags for environment, team, domain, owner, and cost center
#
# The spoke model replaces the fixed raw/curated pattern with a scalable,
# domain-driven design that supports multiple teams and data zones.
#
# To enable: provide data_mesh_spokes in terraform.tfvars, e.g.:
#
# data_mesh_spokes = {
#   sales = {
#     team       = "SALES"
#     domain     = "SALES"
#     data_zones = ["RAW", "SILVER", "GOLD"]
#     schemas    = ["ORDERS", "CUSTOMERS", "RETURNS"]
#     warehouse = {
#       size         = "X-SMALL"
#       auto_suspend = 60
#       max_clusters = 1
#     }
#     credit_quota = 50
#     owner        = "sales-team@example.com"
#     user_role_map = {
#       "analyst@example.com" = ["RL_DEV_SALES_ANALYST"]
#     }
#   }
#   finance = {
#     team       = "FINANCE"
#     domain     = "FINANCE"
#     data_zones = ["RAW", "SILVER", "GOLD"]
#     schemas    = ["TRANSACTIONS", "BUDGETS", "REPORTS"]
#     warehouse = {
#       size         = "SMALL"
#       auto_suspend = 120
#       max_clusters = 2
#     }
#     credit_quota = 100
#     owner        = "finance-team@example.com"
#     user_role_map = {
#       "engineer@example.com" = ["RL_DEV_FINANCE_ENGINEER"]
#       "steward@example.com"  = ["RL_DEV_FINANCE_STEWARD"]
#     }
#   }
# }

locals {
  # Flatten spokes for schema creation: one row per spoke+zone+schema
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

# Domain databases
resource "snowflake_database" "spoke" {
  for_each = var.data_mesh_spokes

  name                        = "DB_${each.value.domain}_${var.environment}"
  comment                     = "Data Mesh spoke: ${each.key} | Team: ${each.value.team} | Owner: ${each.value.owner}"
  data_retention_time_in_days = 1

  depends_on = [module.landing_zone]
}

# Data zone schemas (RAW, SILVER, GOLD) per spoke
resource "snowflake_schema" "spoke_zone" {
  for_each = {
    for s in local.spoke_schemas : "${s.spoke_key}.${s.zone}" => s
  }

  database = snowflake_database.spoke[each.value.spoke_key].name
  name     = each.value.zone
  comment  = "Data zone ${each.value.zone} for ${each.value.spoke_key} spoke"
}

# Business schemas within each data zone
resource "snowflake_schema" "spoke_business" {
  for_each = {
    for s in local.spoke_schemas : "${s.spoke_key}.${s.zone}.${s.schema}" => s
  }

  database = snowflake_database.spoke[each.value.spoke_key].name
  name     = "${each.value.zone}_${each.value.schema}"
  comment  = "Business schema ${each.value.schema} in ${each.value.zone} for ${each.value.spoke_key}"
}

# Domain-specific warehouses
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

# Resource monitors per spoke
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

# Tag associations for spoke databases
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
