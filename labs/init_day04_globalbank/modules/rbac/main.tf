# Bloc RBAC du projet GlobalBank

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  owner_tag = "owner: platform-team | env: ${var.environment}"
}

resource "snowflake_account_role" "access_roles" {
  for_each = var.roles

  name    = "${var.prefix}_${each.value.suffix}${local.suffix}"
  comment = "${each.value.comment} | ${local.owner_tag}"

  depends_on = []

  lifecycle {
    ignore_changes = all
  }
}
