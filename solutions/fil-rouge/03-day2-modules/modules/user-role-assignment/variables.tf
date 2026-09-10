variable "users" {
  type = map(object({
    roles             = list(string)
    default_warehouse = optional(string)
    default_role      = optional(string)
    comment           = optional(string)
  }))
  description = "Map of username => { roles, default_warehouse, default_role, comment }"
}
