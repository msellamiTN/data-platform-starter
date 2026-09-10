# Module: rbac

Creates Snowflake account roles, role hierarchy, privilege grants, and future grants from a data-driven `role_definitions` map using the `ENV_TEAM_ROLE` naming convention.

## Purpose

This module provisions the RBAC layer for the data platform:
- **Role Creation**: All roles are created from the `role_definitions` variable map, named `RL_{SUFFIX}_{ENV}`
- **Role Hierarchy**: Each role is granted to its `parent_role` (system role or another role key)
- **Warehouse Grants**: Configurable privileges on the ETL warehouse per role
- **Database Grants**: Configurable privileges on RAW/CURATED databases per role
- **Future Grants**: Configurable future grants on tables/views per role and database

## Naming Convention

Roles follow the `ENV_TEAM_ROLE` pattern: `RL_{ROLE_SUFFIX}_{ENVIRONMENT}`

Examples:
- `RL_SYSADMIN_DEV` — technical role
- `RL_DATA_ENGINEER_DEV` — business role
- `RL_DATA_STEWARD_TEST` — business role

## Usage

### Default configuration (built-in roles)

```hcl
module "rbac" {
  source = "../../modules/rbac"

  environment           = "DEV"
  raw_database_name     = module.landing_zone.raw_database_name
  curated_database_name = module.landing_zone.curated_database_name
  etl_warehouse_name    = module.landing_zone.warehouse_names["etl"]
}
```

### Custom role definitions

```hcl
module "rbac" {
  source = "../../modules/rbac"

  environment           = "DEV"
  raw_database_name     = module.landing_zone.raw_database_name
  curated_database_name = module.landing_zone.curated_database_name
  etl_warehouse_name    = module.landing_zone.warehouse_names["etl"]

  role_definitions = {
    sysadmin = {
      parent_role      = "SYSADMIN"
      business         = false
      comment          = "Technical Sysadmin"
      warehouse_grants = []
      database_grants  = {}
      future_grants    = {}
    }
    data_engineer = {
      parent_role      = "sysadmin"
      business         = true
      comment          = "Data Engineer"
      warehouse_grants = ["USAGE", "OPERATE"]
      database_grants = {
        raw = ["USAGE", "CREATE SCHEMA"]
      }
      future_grants = {
        raw_tables = {
          privileges  = ["SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE"]
          object_type = "TABLES"
          in_database = "raw"
        }
      }
    }
  }
}
```

## Inputs

| Name | Type | Required | Default | Description |
|------|------|----------|---------|-------------|
| `environment` | string | yes | | `DEV`, `TEST`, or `PROD` |
| `raw_database_name` | string | yes | | Name of the RAW database |
| `curated_database_name` | string | yes | | Name of the CURATED database |
| `etl_warehouse_name` | string | yes | | Name of the ETL warehouse |
| `analytics_warehouse_name` | string | no | `""` | Analytics warehouse name |
| `role_definitions` | map(object) | no | (see below) | Map of role definitions |

### Default role_definitions

| Key | Full Name | Parent | Type |
|-----|-----------|--------|------|
| `sysadmin` | `RL_SYSADMIN_{ENV}` | SYSADMIN | Technical |
| `securityadmin` | `RL_SECURITYADMIN_{ENV}` | SECURITYADMIN | Technical |
| `useradmin` | `RL_USERADMIN_{ENV}` | USERADMIN | Technical |
| `data_analyst` | `RL_DATA_ANALYST_{ENV}` | data_engineer | Business |
| `data_engineer` | `RL_DATA_ENGINEER_{ENV}` | sysadmin | Business |
| `data_steward` | `RL_DATA_STEWARD_{ENV}` | data_analyst | Business |

## Outputs

| Name | Description |
|------|-------------|
| `role_names` | Map of all role names (key => full name) |
| `business_role_names` | Map of business role names only |
| `technical_role_names` | Map of technical role names only |
