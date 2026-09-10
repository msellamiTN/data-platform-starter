# Module: landing-zone

Creates the Snowflake landing zone: databases (RAW + CURATED), warehouses, schemas, resource monitors, and governance tags.

## Purpose

This module provisions the foundational Snowflake objects for a data platform:
- **Databases**: `DB_RAW_{ENV}` and `DB_CURATED_{ENV}` with configurable data retention
- **Warehouses**: Dynamically created from a map, with auto-suspend, scaling, and resource monitor attachment
- **Schemas**: Business schemas (e.g., SALES, FINANCE, MARKETING) created via `for_each` in the RAW database
- **Resource Monitor**: Monthly credit quota with notify/suspend triggers (FinOps)
- **Tags**: `TAG_COST_CENTER`, `TAG_ENVIRONMENT`, `TAG_TEAM` with tag associations on databases and warehouses

## Usage

```hcl
module "landing_zone" {
  source = "../../modules/landing-zone"

  environment         = "DEV"
  project             = "DATAPLATFORM"
  schemas             = ["SALES", "FINANCE", "MARKETING"]
  data_retention_days = 1
  credit_quota        = 100

  warehouses = {
    etl = {
      size         = "X-SMALL"
      auto_suspend = 60
      max_clusters = 2
    }
    analytics = {
      size         = "SMALL"
      auto_suspend = 120
    }
  }
}
```

## Inputs

| Name | Type | Description | Default |
|------|------|-------------|---------|
| `environment` | `string` | Environment suffix (DEV, TEST, PROD) | — (required) |
| `project` | `string` | Project prefix for naming | `DATAPLATFORM` |
| `schemas` | `set(string)` | Business schemas in RAW database | `["RAW", "SILVER", "GOLD"]` |
| `warehouses` | `map(object)` | Map of warehouse name to config (size, auto_suspend, max_clusters) | `{ etl = { size = "X-SMALL" }, analytics = { size = "SMALL" } }` |
| `data_retention_days` | `number` | Time Travel retention in days | `1` |
| `credit_quota` | `number` | Monthly credit quota for resource monitor | `100` |

## Outputs

| Name | Description |
|------|-------------|
| `raw_database_name` | Name of the RAW database |
| `curated_database_name` | Name of the CURATED database |
| `database_names` | Map: `{ raw = ..., curated = ... }` |
| `warehouse_names` | Map of warehouse names by key |
| `schema_names` | List of created schema names |
| `resource_monitor_name` | Name of the resource monitor |
| `tag_names` | Map of tag names: `{ cost_center, environment }` |
