# Implementation du module

locals {
  suffix    = var.environment == "dev" ? "" : "_${upper(var.environment)}"
  owner_tag = "owner: ${var.owner} | env: ${var.environment}"
}

# Exemple : remplacer par la ressource principale du module
# resource "snowflake_xxx" "this" {
#   name    = "${var.prefix}_...${local.suffix}"
#   comment = "... | ${local.owner_tag}"
# }
