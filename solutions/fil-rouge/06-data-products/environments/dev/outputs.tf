output "data_products" {
  description = "Published structural contracts by domain"
  value = {
    for domain, product in module.data_product : domain => {
      database      = product.database_name
      schemas       = product.schema_names
      stage         = product.stage_name
      reader_role   = product.reader_role_name
      producer_role = product.producer_role_name
    }
  }
}
