# Bloc Compute du projet GlobalBank

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  owner_tag = "owner: platform-team | env: ${var.environment}"
}

resource "snowflake_warehouse" "service" {
  for_each = var.warehouses

  name                = "${var.prefix}_${each.value.suffix}${local.suffix}"
  warehouse_size      = var.warehouse_size
  comment             = "${each.value.comment} | ${local.owner_tag}"
  auto_resume         = true
  auto_suspend        = each.value.auto_suspend
  initially_suspended = true
}
