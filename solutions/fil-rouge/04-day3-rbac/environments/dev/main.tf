module "landing_zone" {
  source = "../../../03-day2-modules/modules/landing-zone"

  environment = var.environment
  schemas     = var.schemas
}

module "rbac" {
  source = "../../../03-day2-modules/modules/rbac"

  environment           = var.environment
  raw_database_name     = module.landing_zone.raw_database_name
  curated_database_name = module.landing_zone.curated_database_name
  etl_warehouse_name    = module.landing_zone.warehouse_names["etl"]
}

resource "snowflake_file_format" "csv_raw" {
  depends_on = [module.landing_zone]

  name                         = "FF_CSV_RAW"
  database                     = module.landing_zone.raw_database_name
  schema                       = "INGESTION"
  format_type                  = "CSV"
  field_optionally_enclosed_by = "\""
  skip_header                  = 1
  comment                      = "CSV format for raw ingestion"
}

resource "snowflake_stage_internal" "internal_raw" {
  depends_on = [module.landing_zone]

  name     = "STG_INTERNAL_RAW"
  database = module.landing_zone.raw_database_name
  schema   = "INGESTION"
  comment  = "Internal stage for lab ingestion"
}
