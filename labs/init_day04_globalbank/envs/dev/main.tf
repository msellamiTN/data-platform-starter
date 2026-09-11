# Assemblage du puzzle GlobalBank — DEV
# Phase 1 : bootstraps techniques (Team Platform)

module "rbac" {
  source = "../../modules/rbac"

  prefix      = var.prefix
  environment = var.environment
  roles       = var.roles
}

module "compute" {
  source = "../../modules/compute"

  prefix         = var.prefix
  environment    = var.environment
  warehouse_size = "X-SMALL"
  warehouses     = var.warehouses
}

# Phase 2 : spokes metier (Data Engineering, Business Data, BI)

module "landing_zone" {
  source = "../../modules/landing-zone"

  prefix       = var.prefix
  environment  = var.environment
  zone         = "RAW"
  schema_name  = "LANDING"
  audit_column = "LOAD_TS"
  tables       = var.raw_tables

  depends_on = [module.rbac, module.compute]
}

module "data_domain" {
  source = "../../modules/data-domain"

  prefix         = var.prefix
  environment    = var.environment
  domain         = "CUSTOMER"
  classification = "INTERNE"
  tables         = var.domain_tables

  depends_on = [module.rbac, module.compute]
}

module "data_mart" {
  source = "../../modules/data-mart"

  prefix      = var.prefix
  environment = var.environment
  mart        = "CUSTOMER"
  audience    = "RESEAU"
  mart_tables = var.mart_tables

  depends_on = [module.rbac, module.compute]
}
