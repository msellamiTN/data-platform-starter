variable "snowflake_organization" { type = string }
variable "snowflake_account" { type = string }
variable "snowflake_user" {
  type    = string
  default = "TERRAFORM_SVC"
}
variable "snowflake_role" {
  type    = string
  default = "ACCOUNTADMIN"
}
variable "deployment_mode" {
  type    = string
  default = "training"

  validation {
    condition     = contains(["training", "production"], var.deployment_mode)
    error_message = "deployment_mode must be 'training' or 'production'."
  }
}
variable "private_key_path" {
  type      = string
  sensitive = true
  default   = ""
}

variable "snowflake_password" {
  type      = string
  sensitive = true
  default   = ""
}
variable "environment" {
  type    = string
  default = "TEST"
}
variable "schemas" {
  type    = set(string)
  default = ["SALES", "FINANCE"]
}
