locals {
  warehouse_name = "WH_ETL_${var.environment}"
}

module "data_product" {
  for_each = var.data_products
  source   = "../../../03-day2-modules/modules/data-product"

  providers = {
    snowflake.sysadmin      = snowflake.sysadmin
    snowflake.securityadmin = snowflake.securityadmin
  }

  domain              = upper(each.key)
  environment         = var.environment
  owner_team          = each.value.owner_team
  warehouse_name      = local.warehouse_name
  data_retention_days = each.value.data_retention_days
}
