module "landing_zone" {
  source = "../../modules/landing-zone"

  environment         = var.environment
  schemas             = var.schemas
  data_retention_days = 1

  warehouses = {
    etl = {
      size = "X-SMALL"
    }
    analytics = {
      size = "SMALL"
    }
  }
}
