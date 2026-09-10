# Create all roles from role_definitions map
resource "snowflake_account_role" "this" {
  for_each = var.role_definitions

  name    = local.role_names[each.key]
  comment = "${each.value.comment} - ${var.environment}"
}

# Role hierarchy: grant each role to its parent
resource "snowflake_grant_account_role" "hierarchy" {
  for_each = var.role_definitions

  role_name        = snowflake_account_role.this[each.key].name
  parent_role_name = local.parent_role_names[each.key]

  depends_on = [snowflake_account_role.this]
}

# Warehouse grants
resource "snowflake_grant_privileges_to_account_role" "warehouse" {
  for_each = {
    for key, def in var.role_definitions : key => def
    if length(def.warehouse_grants) > 0
  }

  account_role_name = snowflake_account_role.this[each.key].name
  privileges        = each.value.warehouse_grants
  on_account_object {
    object_type = "WAREHOUSE"
    object_name = var.etl_warehouse_name
  }

  depends_on = [snowflake_account_role.this]
}

# Database grants
resource "snowflake_grant_privileges_to_account_role" "database" {
  for_each = {
    for pair in flatten([
      for role_key, def in var.role_definitions : [
        for db_key, privileges in def.database_grants : {
          role_key   = role_key
          db_key     = db_key
          privileges = privileges
        }
      ]
    ]) : "${pair.role_key}.${pair.db_key}" => pair
  }

  account_role_name = snowflake_account_role.this[each.value.role_key].name
  privileges        = each.value.privileges
  on_account_object {
    object_type = "DATABASE"
    object_name = local.database_name_map[each.value.db_key]
  }

  depends_on = [snowflake_account_role.this]
}

# Future grants on schema objects
resource "snowflake_grant_privileges_to_account_role" "future" {
  for_each = {
    for pair in flatten([
      for role_key, def in var.role_definitions : [
        for grant_key, grant in def.future_grants : {
          role_key  = role_key
          grant_key = grant_key
          grant     = grant
        }
      ]
    ]) : "${pair.role_key}.${pair.grant_key}" => pair
  }

  account_role_name = snowflake_account_role.this[each.value.role_key].name
  privileges        = each.value.grant.privileges
  on_schema_object {
    future {
      object_type_plural = each.value.grant.object_type
      in_database        = local.database_name_map[each.value.grant.in_database]
    }
  }

  depends_on = [snowflake_account_role.this]
}
