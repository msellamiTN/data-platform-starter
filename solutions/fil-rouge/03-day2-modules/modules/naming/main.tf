locals {
  # Canonical ENV_TEAM_ROLE identifier
  env_team_role = var.role != "" ? "${var.environment}_${var.team}_${var.role}" : "${var.environment}_${var.team}"

  # --- Snowflake resource adapters ---

  # Warehouse: WH_${ENV}_${TEAM}_${WORKLOAD}
  warehouse = var.workload != "" ? "WH_${var.environment}_${var.team}_${var.workload}" : "WH_${var.environment}_${var.team}"

  # Business role: RL_${ENV}_${TEAM}_${ROLE}
  role_business = var.role != "" ? "RL_${var.environment}_${var.team}_${var.role}" : "RL_${var.environment}_${var.team}"

  # Technical role: RL_${ENV}_${TEAM}_${ROLE}_TECH
  role_technical = var.role != "" ? "RL_${var.environment}_${var.team}_${var.role}_TECH" : "RL_${var.environment}_${var.team}_TECH"

  # Service user: SVC_${ENV}_${TEAM}_${ROLE}
  service_user = var.role != "" ? "SVC_${var.environment}_${var.team}_${var.role}" : "SVC_${var.environment}_${var.team}"

  # Storage integration: STG_${ENV}_${TEAM}_${DOMAIN}
  storage_integration = var.domain != "" ? "STG_${var.environment}_${var.team}_${var.domain}" : "STG_${var.environment}_${var.team}"

  # Stage: STG_${ENV}_${TEAM}_${DOMAIN}_${FORMAT}
  stage = join("_", compact([
    "STG", var.environment, var.team, var.domain, var.format
  ]))

  # Resource monitor: RM_${ENV}_${TEAM}_${WORKLOAD}
  resource_monitor = var.workload != "" ? "RM_${var.environment}_${var.team}_${var.workload}" : "RM_${var.environment}_${var.team}"

  # Network policy: NP_${ENV}_${TEAM}
  network_policy = "NP_${var.environment}_${var.team}"

  # Tag: TAG_${DOMAIN}_${CLASSIFICATION}
  tag = var.classification != "" ? "TAG_${var.domain}_${var.classification}" : "TAG_${var.domain}"

  # --- Database and schema (business naming, preserved) ---

  # Database: DB_${DOMAIN}_${ENV}
  database = var.domain != "" ? "DB_${var.domain}_${var.environment}" : "DB_${var.environment}"

  # Schema: ${DOMAIN}_${PURPOSE} (purpose passed via domain + workload or custom)
  schema = var.workload != "" ? "${var.domain}_${var.workload}" : var.domain

  # --- Azure resource adapters (lowercase with hyphens) ---

  # Resource group: rg-${project}-${env}
  azure_resource_group = lower("rg-${var.team}-${lower(var.environment)}")

  # Storage account: st${project}${env} (must be lowercase, no hyphens, max 24 chars)
  azure_storage_account = lower("st${substr(var.team, 0, min(length(var.team), 12))}${lower(var.environment)}")

  # Key Vault: kv-${project}-${env}
  azure_key_vault = lower("kv-${var.team}-${lower(var.environment)}")

  # Container name (fixed)
  azure_container = "tfstate"
}
