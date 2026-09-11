# Contrats d'assemblage exposes par l'environnement DEV

output "contracts" {
  value = {
    roles        = module.rbac.role_names
    warehouses   = module.compute.warehouse_names
    landing_zone = module.landing_zone.database_name
    domain       = module.data_domain.domain_contract
    mart         = module.data_mart.mart_contract
  }
  description = "Points d'assemblage du puzzle GlobalBank"
}
