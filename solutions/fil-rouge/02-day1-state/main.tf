resource "snowflake_database" "raw" {
  name                        = local.db_raw_name
  comment                     = local.common_comment
  data_retention_time_in_days = var.environment == "PROD" ? 30 : 1
}

resource "snowflake_warehouse" "etl" {
  name                      = local.wh_etl_name
  comment                   = local.common_comment
  warehouse_size            = var.warehouse_size
  auto_suspend              = 60
  auto_resume               = true
  initially_suspended       = true
  enable_query_acceleration = false
}

resource "snowflake_schema" "raw" {
  for_each = toset(var.schemas)

  database = snowflake_database.raw.name
  name     = each.key
  comment  = "Schema ${each.key} - ${var.environment}"
}
