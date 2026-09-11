# Bloc Landing Zone du projet GlobalBank

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  db_name   = "${var.prefix}_${var.zone}_DB${local.suffix}"
  owner_tag = "owner: data-engineering | env: ${var.environment}"
}

resource "snowflake_database" "this" {
  name    = local.db_name
  comment = "Zone ${var.zone} | ${local.owner_tag}"
}

resource "snowflake_schema" "this" {
  database = snowflake_database.this.name
  name     = var.schema_name
  comment  = "Schema ${var.schema_name} | ${local.owner_tag}"
}

resource "snowflake_table" "tables" {
  for_each = var.tables

  database = snowflake_database.this.name
  schema   = snowflake_schema.this.name
  name     = each.value.name
  comment  = "${each.value.comment} | ${local.owner_tag}"

  column {
    name = "ID"
    type = "NUMBER(38,0)"
  }
  column {
    name = "PAYLOAD"
    type = "VARIANT"
  }
  column {
    name = var.audit_column
    type = "TIMESTAMP_NTZ(9)"
  }
}
