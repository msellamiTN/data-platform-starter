module "landing_zone" {
  source = "../../modules/landing-zone"

  environment         = var.environment
  schemas             = var.schemas
  data_retention_days = 7

  warehouses = {
    etl       = { size = "SMALL", auto_suspend = 120 }
    analytics = { size = "MEDIUM", auto_suspend = 300, max_clusters = 2 }
    reporting = { size = "X-SMALL", auto_suspend = 60 }
  }
}
