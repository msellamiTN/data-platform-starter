# Contrat expose par le module Compute

output "warehouse_names" {
  value       = { for k, w in snowflake_warehouse.service : k => w.name }
  description = "Noms reels des warehouses crees"
}
