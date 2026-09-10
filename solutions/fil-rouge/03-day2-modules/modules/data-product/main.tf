locals {
  database_name   = "DB_${var.domain}_${var.environment}"
  reader_role     = "RL_${var.domain}_READER_${var.environment}"
  producer_role   = "RL_${var.domain}_PRODUCER_${var.environment}"
  medallion_zones = toset(["RAW", "SILVER", "GOLD"])
  comment         = "Data Product ${var.domain} | Owner ${var.owner_team} | ${var.environment}"
}

resource "snowflake_database" "this" {
  provider                    = snowflake.sysadmin
  name                        = local.database_name
  comment                     = local.comment
  data_retention_time_in_days = var.data_retention_days
}

resource "snowflake_schema" "zone" {
  provider = snowflake.sysadmin
  for_each = local.medallion_zones

  database = snowflake_database.this.name
  name     = each.value
  comment  = "${each.value} zone | ${local.comment}"
}

resource "snowflake_stage_internal" "raw" {
  provider = snowflake.sysadmin
  name     = "STG_${var.domain}_RAW_${var.environment}"
  database = snowflake_database.this.name
  schema   = snowflake_schema.zone["RAW"].name
  comment  = local.comment
}

resource "snowflake_account_role" "reader" {
  provider = snowflake.securityadmin
  name     = local.reader_role
  comment  = "Read access | ${local.comment}"
}

resource "snowflake_account_role" "producer" {
  provider = snowflake.securityadmin
  name     = local.producer_role
  comment  = "Produce and transform | ${local.comment}"
}

resource "snowflake_grant_account_role" "reader_to_producer" {
  provider         = snowflake.securityadmin
  role_name        = snowflake_account_role.reader.name
  parent_role_name = snowflake_account_role.producer.name
}

resource "snowflake_grant_privileges_to_account_role" "database_usage" {
  provider = snowflake.securityadmin
  for_each = {
    reader   = snowflake_account_role.reader.name
    producer = snowflake_account_role.producer.name
  }

  account_role_name = each.value
  privileges        = ["USAGE"]
  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.this.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "schema_usage" {
  provider = snowflake.securityadmin
  for_each = {
    for pair in setproduct(keys(snowflake_schema.zone), [snowflake_account_role.reader.name, snowflake_account_role.producer.name]) :
    "${pair[0]}.${pair[1]}" => {
      zone = pair[0]
      role = pair[1]
    }
  }

  account_role_name = each.value.role
  privileges        = ["USAGE"]
  on_schema {
    schema_name = "${snowflake_database.this.name}.${snowflake_schema.zone[each.value.zone].name}"
  }
}

resource "snowflake_grant_privileges_to_account_role" "reader_future_tables" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.reader.name
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "TABLES"
      in_database        = snowflake_database.this.name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "producer_warehouse" {
  provider          = snowflake.securityadmin
  account_role_name = snowflake_account_role.producer.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.warehouse_name
  }
}
