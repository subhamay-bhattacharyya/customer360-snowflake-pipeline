# -- infra/snowflake/tf/locals.tf
# ============================================================================
# Local Values
# ============================================================================

locals {
  # Parse config from JSON file (relative to module path)
  snowflake_config = jsondecode(file("${path.module}/${var.snowflake_config_path}"))

  # ============================================================================
  # Snowflake Configuration
  # ============================================================================

  # Warehouses - add optional prefix to names and grants
  warehouses = {
    for key, wh in lookup(local.snowflake_config, "warehouses", {}) : key => merge(wh, {
      name = var.project_code != "" ? upper("${var.project_code}_${wh.name}") : wh.name
      # Grants - db_provisioner needs USAGE for dynamic table refresh
      grants = [
        { role_name = var.db_provisioner_role, privileges = ["USAGE"] }
      ]
    })
  }

  # Databases with schemas - nested structure
  database_schemas = {
    for db_key, db in lookup(local.snowflake_config, "databases", {}) : db_key => {
      name    = var.project_code != "" ? upper("${var.project_code}_${db.name}") : db.name
      comment = lookup(db, "comment", "")
      schemas = [
        for schema in lookup(db, "schemas", []) : {
          name    = schema.name
          comment = lookup(schema, "comment", "")
        }
      ]
    }
  }

  # Dynamic Tables configuration
  dynamic_tables = {
    dt_emp_dept_lag_60_on_schedule = {
      name         = "DT_EMP_DEPT_LAG_60_ON_SCHEDULE"
      database     = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      schema       = "HR"
      warehouse    = "DYT_LAB_01_WH"
      target_lag   = "60 minutes"
      refresh_mode = "AUTO"
      initialize   = "ON_SCHEDULE"
      comment      = "Employee-Department join with 60 min lag, auto refresh on schedule"
      query = templatefile("${path.module}/templates/dynamic-tables/dyt_emp_dept.tpl", {
        database = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      })
    }
    dt_emp_dept_lag_60_on_create = {
      name         = "DT_EMP_DEPT_LAG_60_ON_CREATE"
      database     = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      schema       = "HR"
      warehouse    = "DYT_LAB_01_WH"
      target_lag   = "60 minutes"
      refresh_mode = "AUTO"
      initialize   = "ON_CREATE"
      comment      = "Employee-Department join with 60 min lag, auto refresh on create"
      query = templatefile("${path.module}/templates/dynamic-tables/dyt_emp_dept.tpl", {
        database = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      })
    }
    dt_emp_dept_downstream_on_create = {
      name         = "DT_EMP_DEPT_DOWNSTREAM_ON_CREATE"
      database     = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      schema       = "HR"
      warehouse    = "DYT_LAB_01_WH"
      target_lag   = "DOWNSTREAM"
      refresh_mode = "AUTO"
      initialize   = "ON_CREATE"
      comment      = "Employee-Department join with downstream lag, auto refresh on create"
      query = templatefile("${path.module}/templates/dynamic-tables/dyt_emp_dept.tpl", {
        database = var.project_code != "" ? upper("${var.project_code}_HRMS") : "HRMS"
      })
    }
  }

  # Tables - flatten from all databases/schemas into a map
  tables = {
    for item in flatten([
      for db_key, db in lookup(local.snowflake_config, "databases", {}) : [
        for schema in lookup(db, "schemas", []) : [
          for table_key, table in lookup(schema, "tables", {}) : {
            key        = "${db_key}_${lower(schema.name)}_${table_key}"
            database   = var.project_code != "" ? upper("${var.project_code}_${db.name}") : db.name
            schema     = schema.name
            name       = table.name
            table_type = lookup(table, "table_type", "PERMANENT")
            comment    = lookup(table, "comment", "")
            columns = [
              for col in table.columns : {
                name     = col.name
                type     = col.type
                nullable = lookup(col, "nullable", true)
                default  = lookup(col, "default", null)
                comment  = lookup(col, "comment", null)
                autoincrement = lookup(col, "autoincrement", null) != null ? {
                  start     = lookup(col.autoincrement, "start", 1)
                  increment = lookup(col.autoincrement, "increment", 1)
                  order     = lookup(col.autoincrement, "order", false)
                } : null
              }
            ]
            primary_key                 = lookup(table, "primary_key", null)
            cluster_by                  = lookup(table, "cluster_by", null)
            data_retention_time_in_days = lookup(table, "data_retention_time_in_days", 1)
            change_tracking             = lookup(table, "change_tracking", false)
            drop_before_create          = lookup(table, "drop_before_create", false)
          }
        ]
      ]
    ]) : item.key => item
  }
}
