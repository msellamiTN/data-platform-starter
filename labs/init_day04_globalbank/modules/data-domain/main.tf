# Bloc Data Domain du projet GlobalBank

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  db_name   = "${var.prefix}_${var.domain}_DB${local.suffix}"
  owner_tag = "owner: business-data | domain: ${lower(var.domain)} | classification: ${var.classification}"
}

resource "snowflake_database" "this" {
  name    = local.db_name
  comment = "Domaine ${var.domain} | ${local.owner_tag}"
}

resource "snowflake_schema" "this" {
  database = snowflake_database.this.name
  name     = "BUSINESS"
  comment  = "Schema metier | ${local.owner_tag}"
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
    name = "LABEL"
    type = "VARCHAR(255)"
  }
  column {
    name = "UPDATED_TS"
    type = "TIMESTAMP_NTZ(9)"
  }
}
