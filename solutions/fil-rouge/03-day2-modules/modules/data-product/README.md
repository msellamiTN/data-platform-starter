# Data Product module

Creates one domain-owned Snowflake data product:

- database `DB_{DOMAIN}_{ENV}`;
- RAW, SILVER and GOLD schemas;
- internal RAW stage;
- producer and reader roles;
- hierarchy, database/schema usage and future SELECT grants.

The caller must provide `snowflake.sysadmin` and `snowflake.securityadmin` aliases. Terraform owns structural objects and grants; Snow CLI owns versioned SQL content deployed into those structures.
