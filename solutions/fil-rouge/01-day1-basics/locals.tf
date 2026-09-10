locals {
  db_raw_name = "DB_RAW_${var.environment}"
  wh_etl_name = "WH_ETL_${var.environment}"

  common_comment = "Managed by Terraform | ${var.project} | ${var.environment}"
}
