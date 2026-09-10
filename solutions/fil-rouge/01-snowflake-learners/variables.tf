# ============================================================
# 01-snowflake-learners — Variables
# ============================================================

variable "learner_count" {
  type        = number
  description = "Number of learner users to create in Snowflake."
  default     = 12
}

variable "learner_prefix_pattern" {
  type        = string
  description = "Pattern for learner prefixes. {i} is replaced with the zero-padded index."
  default     = "APP{i}"
}

variable "learner_username_pattern" {
  type        = string
  description = "Pattern for Snowflake usernames. {i} is replaced with the zero-padded index."
  default     = "apprenant{i}"
}

variable "learner_password_pattern" {
  type        = string
  description = "Pattern for Snowflake passwords. {i} is replaced with the zero-padded index. Must meet Snowflake password policy (14+ chars, 1 digit, 1 uppercase, 1 lowercase)."
  sensitive   = true
  default     = "SnowflakeLearner2026@{i}"
}

variable "default_role" {
  type        = string
  description = "Default role assigned to each learner user."
  default     = "SYSADMIN"
}

variable "mins_to_bypass_mfa" {
  type        = number
  description = "Minutes to bypass MFA for each learner. Maximum 240 (4 hours). Re-run terraform apply to refresh."
  default     = 240
}

variable "must_change_password" {
  type        = bool
  description = "Whether learners must change their password on first login."
  default     = false
}

# ============================================================
# Snowflake provider configuration
# ============================================================

variable "snowflake_organization" {
  type        = string
  description = "Snowflake organization name."
}

variable "snowflake_account" {
  type        = string
  description = "Snowflake account name."
}

variable "snowflake_user" {
  type        = string
  description = "Snowflake instructor user (ACCOUNTADMIN)."
}

variable "snowflake_role" {
  type        = string
  description = "Snowflake instructor role."
  default     = "ACCOUNTADMIN"
}

variable "snowflake_token" {
  type        = string
  description = "Snowflake PAT for the instructor (ACCOUNTADMIN)."
  sensitive   = true
}

# ============================================================
# Azure Key Vault (for storing learner passwords)
# ============================================================

variable "key_vault_id" {
  type        = string
  description = "Resource ID of the Azure Key Vault (from 00-bootstrap output)."
}

variable "store_passwords_in_kv" {
  type        = bool
  description = "Whether to store learner web passwords in Key Vault (as SnowflakePassword-APP01, etc.)."
  default     = true
}
