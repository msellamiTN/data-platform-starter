# Module: user-role-assignment

Creates Snowflake users and assigns roles to them via `snowflake_grant_account_role`.

## Purpose

This module provisions Snowflake users and grants them one or more roles. It is designed to be used after the `landing-zone` and `rbac` modules to complete the access management layer.

## Usage

```hcl
module "users" {
  source = "../../modules/user-role-assignment"

  users = {
    "ANALYST_USER_DEV" = {
      roles            = ["RL_DATA_ANALYST_DEV"]
      default_role     = "RL_DATA_ANALYST_DEV"
      default_warehouse = "WH_ETL_DEV"
    }
    "ENGINEER_USER_DEV" = {
      roles            = ["RL_DATA_ENGINEER_DEV"]
      default_role     = "RL_DATA_ENGINEER_DEV"
      default_warehouse = "WH_ETL_DEV"
    }
  }
}
```

## Inputs

| Name | Type | Description | Default |
|------|------|-------------|---------|
| `users` | `map(object)` | Map of username => { roles, default_warehouse, default_role, comment } | — (required) |

## Outputs

| Name | Description |
|------|-------------|
| `user_names` | List of created user names |
| `user_role_assignments` | Map of user => roles assigned |
