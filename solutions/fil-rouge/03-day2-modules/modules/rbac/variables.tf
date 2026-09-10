variable "environment" {
  type = string

  validation {
    condition     = contains(["DEV", "TEST", "PROD"], var.environment)
    error_message = "environment must be DEV, TEST, or PROD."
  }
}

variable "raw_database_name" {
  type = string
}

variable "curated_database_name" {
  type = string
}

variable "etl_warehouse_name" {
  type = string
}

variable "analytics_warehouse_name" {
  type        = string
  description = "Name of the analytics warehouse for analyst grants. Optional."
  default     = ""
}

variable "role_definitions" {
  type = map(object({
    parent_role      = string
    business         = bool
    comment          = string
    warehouse_grants = optional(list(string), [])
    database_grants  = map(list(string))
    future_grants = map(object({
      privileges  = list(string)
      object_type = string
      in_database = string
      in_schema   = optional(string, "")
    }))
  }))
  description = "Map of role definitions. Each key is a role suffix; the full role name is RL_{SUFFIX}_{ENV}. See README for details."
  default = {
    sysadmin = {
      parent_role      = "SYSADMIN"
      business         = false
      comment          = "Technical Sysadmin role"
      warehouse_grants = []
      database_grants  = {}
      future_grants    = {}
    }
    securityadmin = {
      parent_role      = "SECURITYADMIN"
      business         = false
      comment          = "Technical Securityadmin role"
      warehouse_grants = []
      database_grants  = {}
      future_grants    = {}
    }
    useradmin = {
      parent_role      = "USERADMIN"
      business         = false
      comment          = "Technical Useradmin role"
      warehouse_grants = []
      database_grants  = {}
      future_grants    = {}
    }
    data_analyst = {
      parent_role      = "data_engineer"
      business         = true
      comment          = "Business Data Analyst role"
      warehouse_grants = ["USAGE"]
      database_grants = {
        raw     = ["USAGE"]
        curated = ["USAGE"]
      }
      future_grants = {
        raw_tables = {
          privileges  = ["SELECT"]
          object_type = "TABLES"
          in_database = "raw"
        }
        raw_views = {
          privileges  = ["SELECT"]
          object_type = "VIEWS"
          in_database = "raw"
        }
        curated_tables = {
          privileges  = ["SELECT"]
          object_type = "TABLES"
          in_database = "curated"
        }
      }
    }
    data_engineer = {
      parent_role      = "sysadmin"
      business         = true
      comment          = "Business Data Engineer role"
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
    data_steward = {
      parent_role      = "data_analyst"
      business         = true
      comment          = "Business Data Steward role"
      warehouse_grants = []
      database_grants  = {}
      future_grants = {
        curated_tables = {
          privileges  = ["SELECT"]
          object_type = "TABLES"
          in_database = "curated"
        }
      }
    }
  }
}

locals {
  role_names = {
    for key, def in var.role_definitions : key => "RL_${upper(key)}_${var.environment}"
  }

  database_name_map = {
    raw     = var.raw_database_name
    curated = var.curated_database_name
  }

  parent_role_names = {
    for key, def in var.role_definitions : key => (
      contains(keys(var.role_definitions), def.parent_role) ? local.role_names[def.parent_role] : def.parent_role
    )
  }
}
