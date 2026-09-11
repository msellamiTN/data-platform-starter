# Bloc Data Mart du projet GlobalBank

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  db_name   = "${var.prefix}_${var.mart}_MART${local.suffix}"
  owner_tag = "owner: bi-analytics | mart: ${lower(var.mart)} | audience: ${var.audience}"
}

resource "snowflake_database" "this" {
  name    = local.db_name
  comment = "Data mart ${var.mart} | ${local.owner_tag}"
}

resource "snowflake_schema" "this" {
  database = snowflake_database.this.name
  name     = "MART"
  comment  = "Schema de restitution | ${local.owner_tag}"
}

resource "snowflake_table" "tables" {
  for_each = var.mart_tables

  database = snowflake_database.this.name
  schema   = snowflake_schema.this.name
  name     = each.value.name
  comment  = "${each.value.comment} | ${local.owner_tag}"

  column {
    name = "ID"
    type = "NUMBER(38,0)"
  }
  column {
    name = "METRIC"
    type = "VARCHAR(255)"
  }
  column {
    name = "VALUE"
    type = "NUMBER(38,4)"
  }
  column {
    name = "AS_OF_DATE"
    type = "DATE"
  }
}
