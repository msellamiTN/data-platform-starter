locals {
  comment = "Managed by Terraform | ${var.project} | ${var.environment}"
}

# Cost Optimization: Resource Monitor to prevent overrun budget
# resource "snowflake_resource_monitor" "this" {
#   name         = "RM_BUDGET_${var.environment}"
#   credit_quota = var.credit_quota
#
#   frequency       = "MONTHLY"
#   start_timestamp = "IMMEDIATELY"
#
#   notify_triggers           = [75, 90]
#   suspend_trigger           = 100
#   suspend_immediate_trigger = 110
# }

resource "snowflake_database" "raw" {
  name                        = "DB_RAW_${var.environment}"
  comment                     = local.comment
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_database" "curated" {
  name                        = "DB_CURATED_${var.environment}"
  comment                     = local.comment
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "ingestion" {
  database = snowflake_database.raw.name
  name     = "INGESTION"
  comment  = "Ingestion layer - ${var.environment}"
}

resource "snowflake_schema" "business" {
  for_each = toset(var.schemas)

  database = snowflake_database.raw.name
  name     = each.key
  comment  = "Business schema ${each.key} - ${var.environment}"
}

# Operational Excellence & Governance: Tags for cost allocation
resource "snowflake_tag" "cost_center" {
  name           = "TAG_COST_CENTER"
  database       = snowflake_database.raw.name
  schema         = snowflake_schema.ingestion.name
  allowed_values = ["FINANCE", "SALES", "MARKETING", "DEVOPSEOPS"]
}

resource "snowflake_tag" "environment" {
  name           = "TAG_ENVIRONMENT"
  database       = snowflake_database.raw.name
  schema         = snowflake_schema.ingestion.name
  allowed_values = ["DEV", "TEST", "PROD"]
}

resource "snowflake_tag" "team" {
  name           = "TAG_TEAM"
  database       = snowflake_database.raw.name
  schema         = snowflake_schema.ingestion.name
  allowed_values = ["DATA_ENG", "DATA_ANALYST", "BI", "QA"]
}

resource "snowflake_tag" "owner" {
  name           = "TAG_OWNER"
  database       = snowflake_database.raw.name
  schema         = snowflake_schema.ingestion.name
  allowed_values = []
}

resource "snowflake_tag_association" "db_raw_env" {
  object_identifiers = [snowflake_database.raw.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.environment.name}"
  tag_value          = var.environment
}

resource "snowflake_tag_association" "db_raw_cc" {
  object_identifiers = [snowflake_database.raw.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.cost_center.name}"
  tag_value          = "FINANCE"
}

resource "snowflake_tag_association" "db_raw_team" {
  object_identifiers = [snowflake_database.raw.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.team.name}"
  tag_value          = "DATA_ENG"
}

resource "snowflake_tag_association" "db_curated_env" {
  object_identifiers = [snowflake_database.curated.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.environment.name}"
  tag_value          = var.environment
}

resource "snowflake_tag_association" "db_curated_cc" {
  object_identifiers = [snowflake_database.curated.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.cost_center.name}"
  tag_value          = "SALES"
}

resource "snowflake_tag_association" "db_curated_team" {
  object_identifiers = [snowflake_database.curated.name]
  object_type        = "DATABASE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.team.name}"
  tag_value          = "DATA_ANALYST"
}

resource "snowflake_warehouse" "this" {
  for_each = var.warehouses

  name                = "WH_${upper(each.key)}_${var.environment}"
  comment             = local.comment
  warehouse_size      = each.value.size
  auto_suspend        = each.value.auto_suspend
  auto_resume         = true
  initially_suspended = true
  max_cluster_count   = each.value.max_clusters
  min_cluster_count   = 1
  scaling_policy      = "STANDARD"

  # Link Resource Monitor to Warehouse for cost controls
  # resource_monitor = snowflake_resource_monitor.this.name
}

# Tag Warehouses for tracking
resource "snowflake_tag_association" "wh_env" {
  for_each = snowflake_warehouse.this

  object_identifiers = [each.value.name]
  object_type        = "WAREHOUSE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.environment.name}"
  tag_value          = var.environment
}

resource "snowflake_tag_association" "wh_cc" {
  for_each = snowflake_warehouse.this

  object_identifiers = [each.value.name]
  object_type        = "WAREHOUSE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.cost_center.name}"
  tag_value          = each.key == "etl" ? "FINANCE" : "SALES"
}

resource "snowflake_tag_association" "wh_team" {
  for_each = snowflake_warehouse.this

  object_identifiers = [each.value.name]
  object_type        = "WAREHOUSE"
  tag_id             = "${snowflake_database.raw.name}.${snowflake_schema.ingestion.name}.${snowflake_tag.team.name}"
  tag_value          = each.key == "etl" ? "DATA_ENG" : "DATA_ANALYST"
}
