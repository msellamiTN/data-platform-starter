# Naming Standard Module

This module implements the `ENV_TEAM_ROLE` naming convention for the Terraform & Snowflake training repository. It provides computed resource names for Snowflake and Azure resources based on validated inputs.

## Usage

```hcl
module "naming" {
  source     = "../../../03-day2-modules/modules/naming"
  environment = "DEV"
  team       = "DATA_ENG"
  role       = "ENGINEER"
  domain     = "RAW"
  workload   = "ETL"
  format     = "CSV"
}

# Use outputs directly
resource "snowflake_warehouse" "etl" {
  name    = module.naming.warehouse           # WH_DEV_DATA_ENG_ETL
  # ...
}

resource "snowflake_role" "engineer" {
  name    = module.naming.role_business       # RL_DEV_DATA_ENG_ENGINEER
  # ...
}
```

## Inputs

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `environment` | string | yes | `DEV`, `TEST`, or `PROD` (uppercase) |
| `team` | string | yes | Domain team (e.g. `DATA_ENG`, `ANALYTICS`) |
| `role` | string | no | Functional role (e.g. `ENGINEER`, `ANALYST`) |
| `domain` | string | no | Data mesh domain (e.g. `RAW`, `CURATED`, `GOLD`) |
| `workload` | string | no | Workload type (e.g. `ETL`, `BATCH`, `SERVING`) |
| `format` | string | no | File format (e.g. `CSV`, `PARQUET`, `JSON`) |
| `classification` | string | no | Data classification (e.g. `PII`, `SENSITIVE`) |

## Outputs

| Name | Pattern | Example |
|------|---------|---------|
| `env_team_role` | `ENV_TEAM_ROLE` | `DEV_DATA_ENG_ENGINEER` |
| `warehouse` | `WH_ENV_TEAM_WORKLOAD` | `WH_DEV_DATA_ENG_ETL` |
| `role_business` | `RL_ENV_TEAM_ROLE` | `RL_DEV_DATA_ENG_ENGINEER` |
| `role_technical` | `RL_ENV_TEAM_ROLE_TECH` | `RL_DEV_DATA_ENG_ENGINEER_TECH` |
| `service_user` | `SVC_ENV_TEAM_ROLE` | `SVC_DEV_DATA_ENG_ENGINEER` |
| `storage_integration` | `STG_ENV_TEAM_DOMAIN` | `STG_DEV_DATA_ENG_RAW` |
| `stage` | `STG_ENV_TEAM_DOMAIN_FORMAT` | `STG_DEV_DATA_ENG_RAW_CSV` |
| `resource_monitor` | `RM_ENV_TEAM_WORKLOAD` | `RM_DEV_DATA_ENG_ETL` |
| `network_policy` | `NP_ENV_TEAM` | `NP_DEV_DATA_ENG` |
| `tag` | `TAG_DOMAIN_CLASSIFICATION` | `TAG_RAW_PII` |
| `database` | `DB_DOMAIN_ENV` | `DB_RAW_DEV` |
| `schema` | `DOMAIN_WORKLOAD` | `RAW_ETL` |
| `azure_resource_group` | `rg-team-env` | `rg-data_eng-dev` |
| `azure_storage_account` | `stteamenv` | `stdata_engdev` |
| `azure_key_vault` | `kv-team-env` | `kv-data_eng-dev` |
| `azure_container` | fixed | `tfstate` |

## Validation

All inputs are validated for:
- `environment`: must be `DEV`, `TEST`, or `PROD`
- All naming segments: uppercase alphanumeric with underscores, starting with a letter

## Design Decisions

- Database and schema names use **business naming** (`DB_RAW_DEV`), not `ENV_TEAM_ROLE`, to preserve existing state and avoid disruptive renames.
- Azure resource names follow Azure conventions (lowercase with hyphens).
- The module is pure computation (no resources created), making it safe to include in any root.
