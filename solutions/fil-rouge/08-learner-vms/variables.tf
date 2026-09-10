# ============================================================
# 08-learner-vms — Variables
# ============================================================

variable "azure_location" {
  type        = string
  description = "Azure region for the learner VMs."
  default     = "eastus"
}

variable "project_name" {
  type        = string
  description = "Prefix for naming resources."
  default     = "data2ai-tf-training"
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group for the learner VMs."
  default     = "rg-data2ai-learner-vms"
}

variable "learner_count" {
  type        = number
  description = "Number of learner VMs to create (one per learner, APP01..APPnn)."
  default     = 12
}

# ============================================================
# Identifiants — REUTILISE littéralement 01-snowflake-learners
# pour que l'apprenant n'ait qu'un seul couple login/mot de passe
# a retenir (Snowflake web UI et RDP VM).
# ============================================================

variable "learner_username_pattern" {
  type        = string
  description = "Pattern for the VM admin username. {i} is replaced with the zero-padded index. Must match 01-snowflake-learners.learner_username_pattern to keep credentials unified."
  default     = "apprenant{i}"
}

variable "learner_password_pattern" {
  type        = string
  description = "Pattern for the VM admin password. {i} is replaced with the zero-padded index. Must match 01-snowflake-learners.learner_password_pattern (default SnowflakeLearner2026@{i}) so the RDP password equals the Snowflake password."
  sensitive   = true
  default     = "SnowflakeLearner2026@{i}"
}

# ============================================================
# VM configuration
# ============================================================

variable "vm_size" {
  type        = string
  description = "VM size for each learner VM."
  default     = "Standard_D2ads_v7"
}

variable "vm_size_overrides" {
  type        = map(string)
  description = "Optional per-learner VM size overrides, keyed by learner index (e.g. { \"3\" = \"Standard_D2s_v4\" }). Used to spread VMs across SKU families when a family quota is saturated."
  default     = {}
}

variable "windows_sku" {
  type        = string
  description = "Windows desktop image SKU."
  default     = "win11-25h2-pro"
}

variable "os_disk_size_gb" {
  type        = number
  description = "OS disk size in GB for each learner VM."
  default     = 127
}

# ============================================================
# Networking / RDP access
# ============================================================

variable "vnet_address_space" {
  type        = list(string)
  description = "Address space for the learner VMs VNet."
  default     = ["10.30.0.0/16"]
}

variable "subnet_address_prefixes" {
  type        = list(string)
  description = "Subnet address prefixes for the learner VMs."
  default     = ["10.30.1.0/24"]
}

variable "rdp_allowed_source_prefixes" {
  type        = list(string)
  description = "Source IP prefixes allowed to reach RDP (3389) on the learner VMs. Restrict to the training room / VPN range before the session; default '*' allows RDP from the Internet."
  default     = ["*"]
}

# ============================================================
# Provisioning (Custom Script Extension)
# ============================================================

variable "repo_url" {
  type        = string
  description = "Git URL of the starter repo to clone on each VM."
  default     = "https://github.com/msellamiTN/data-platform-starter.git"
}

variable "install_root" {
  type        = string
  description = "Machine-wide install root passed to Install-Tools.ps1 -InstallRoot. Using a fixed machine path (not $HOME) avoids installing under the SYSTEM profile used by the Custom Script Extension."
  default     = "C:\\data2ai"
}

variable "repo_local_path" {
  type        = string
  description = "Local path on the VM where the starter repo is cloned."
  default     = "C:\\Data2AI-Labs\\data-platform"
}

# ============================================================
# Auto-shutdown (cost control)
# ============================================================

variable "auto_shutdown_time" {
  type        = string
  description = "Daily auto-shutdown time (HHmm, 24h)."
  default     = "1900"
}

variable "auto_shutdown_timezone" {
  type        = string
  description = "Timezone for the auto-shutdown schedule."
  default     = "Central European Standard Time"
}

# ============================================================
# Azure provider
# ============================================================

# ============================================================
# Snowflake / Azure connection info (written to config/shared.env)
# ============================================================

variable "snowflake_organization" {
  type        = string
  description = "Snowflake organization identifier (e.g. ZVFXOZW)."
  default     = ""
}

variable "snowflake_account" {
  type        = string
  description = "Snowflake account identifier (e.g. PM71247)."
  default     = ""
}

variable "snowflake_role" {
  type        = string
  description = "Snowflake role for the shared training user."
  default     = "SYSADMIN"
}

variable "snowflake_user" {
  type        = string
  description = "Shared Snowflake training user (not per-learner)."
  default     = "TRAINING_USER"
}

variable "snowflake_warehouse" {
  type        = string
  description = "Snowflake warehouse for labs."
  default     = "COMPUTE_WH"
}

variable "snowflake_database" {
  type        = string
  description = "Snowflake database for labs."
  default     = "TRAINING_DB"
}

variable "snowflake_schema" {
  type        = string
  description = "Snowflake schema for labs."
  default     = "PUBLIC"
}

variable "azure_tenant_id" {
  type        = string
  description = "Azure AD tenant ID (written to config/shared.env)."
  default     = ""
}

variable "key_vault_name" {
  type        = string
  description = "Name of the shared Key Vault where learner PATs are stored."
  default     = ""
}

variable "key_vault_resource_group_name" {
  type        = string
  description = "Resource group containing the shared Key Vault."
  default     = "rg-data2ai-tf-state"
}

# ============================================================
# Disk / image
# ============================================================

variable "os_disk_type" {
  type        = string
  description = "Storage account type for the OS disk."
  default     = "Premium_LRS"
}

# ============================================================
# Auto-shutdown toggle
# ============================================================

variable "auto_shutdown_enabled" {
  type        = bool
  description = "Enable daily auto-shutdown for cost control."
  default     = true
}

# ============================================================
# Azure provider
# ============================================================

variable "arm_subscription_id" {
  type        = string
  description = "Azure subscription ID for the azurerm provider."
  default     = ""
}
