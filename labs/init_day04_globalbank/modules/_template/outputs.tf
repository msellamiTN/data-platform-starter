# Contrat de sortie du module

output "module_contract" {
  value = {
    prefix      = var.prefix
    environment = var.environment
    owner       = var.owner
  }
  description = "Contrat minimal expose par le module"
}
