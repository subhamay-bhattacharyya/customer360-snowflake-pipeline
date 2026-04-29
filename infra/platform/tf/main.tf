# -- infra/platform/tf/main.tf (Platform Module)
# ============================================================================
# Snowflake Lakehouse - Platform Orchestration
# ============================================================================
#
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 1: AWS Resources                                     │
# ├─────────────────────────────────────────────────────────────┤
# │  • 1.1 S3 Bucket (landing zone for data files)              │
# │  • 1.2 IAM Role (with placeholder trust policy)             │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 2: Snowflake Resources                               │
# ├─────────────────────────────────────────────────────────────┤
# │  • 2.1 Warehouses                                           │
# │  • 2.2 Databases & Schemas                                  │
# │  • 2.3 File Formats                                         │
# │  • 2.4 Storage Integration                                  │
# │  • 2.5 Stages                                               │
# │  • 2.6 Tables                                               │
# │  • 2.7 Table Grants                                         │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 3: AWS Trust Policy Update                           │
# ├─────────────────────────────────────────────────────────────┤
# │  • 3.1 Update IAM Role trust policy with Snowflake creds    │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 4: Snowpipes (BRONZE layer)                          │
# ├─────────────────────────────────────────────────────────────┤
# │  • 4.1 Snowpipe creation                                    │
# │  • 4.2 S3 Event Notifications for auto-ingest               │
# └─────────────────────────────────────────────────────────────┘
#                             │
#                             ▼
# ┌─────────────────────────────────────────────────────────────┐
# │  PHASE 5: Dynamic Tables (SILVER layer)                     │
# ├─────────────────────────────────────────────────────────────┤
# │  • 5.1 Grants for Dynamic Table creation                    │
# │  • 5.2 Dynamic Table Module                                 │
# └─────────────────────────────────────────────────────────────┘
#
# ============================================================================

# ============================================================================
# PHASE 1: AWS Resources
# ============================================================================

# ----------------------------------------------------------------------------
# • 1.1 S3 Bucket for Snowflake external stage
# ----------------------------------------------------------------------------
module "s3" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-s3.git//modules/bucket?ref=v1.0.0"

  s3_config = local.s3_config
}

# ----------------------------------------------------------------------------
# • 1.1b S3 Bucket Lifecycle Rules
# Applied here because terraform-aws-s3 v1.0.0 does not expose a
# lifecycle_rules field on its s3_config variable. Reads directly from the
# AWS config JSON (aws.s3.lifecycle_rules); count gates on presence so envs
# without the field (test/prod today) skip the resource entirely.
# ----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = length(try(local.aws_config.s3.lifecycle_rules, [])) > 0 ? 1 : 0

  bucket = module.s3.bucket_id

  dynamic "rule" {
    for_each = local.aws_config.s3.lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.enabled ? "Enabled" : "Disabled"

      filter {
        prefix = lookup(rule.value, "prefix", "")
      }

      expiration {
        days = rule.value.expiration_days
      }
    }
  }

  depends_on = [module.s3]
}

# ----------------------------------------------------------------------------
# • 1.2 IAM Role for Snowflake storage integration (initial with placeholder trust)
# ----------------------------------------------------------------------------
module "iam_role" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-iam.git//modules/role?ref=v1.0.0"

  iam_role = local.iam_role_config

  depends_on = [module.s3]
}

# ============================================================================
# PHASE 2: Snowflake Resources
# ============================================================================

# ----------------------------------------------------------------------------
# • 2.1 Warehouses
# ----------------------------------------------------------------------------
module "warehouse" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-warehouse.git?ref=v3.0.0"

  providers = {
    snowflake = snowflake.warehouse_provisioner
  }

  warehouse_configs = local.warehouses
}

# ----------------------------------------------------------------------------
# • 2.2 Databases and Schemas
# ----------------------------------------------------------------------------
module "database_schemas" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-database-schema.git?ref=v1.3.0"

  providers = {
    snowflake = snowflake.db_provisioner
  }

  database_configs = local.database_schemas
}

# ----------------------------------------------------------------------------
# • 2.3 File Formats
# ----------------------------------------------------------------------------
module "file_formats" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-file-format.git?ref=v1.2.0"

  providers = {
    snowflake = snowflake.data_object_provisioner
  }

  file_format_configs = local.file_formats

  depends_on = [module.database_schemas]
}

# ----------------------------------------------------------------------------
# • 2.4 Storage Integrations
# ----------------------------------------------------------------------------
module "storage_integrations" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-storage-integration.git?ref=v1.2.0"

  providers = {
    snowflake = snowflake.ingest_object_provisioner
  }

  storage_integration_configs = local.storage_integrations

  depends_on = [module.file_formats]
}

# ----------------------------------------------------------------------------
# • 2.4b API Integrations
# Account-level integration object (no DB/schema dependency). Currently no
# downstream consumers in the pipeline; staged for future Streamlit-deploy
# work. Pinned to a feature branch until the module publishes a stable tag.
# ----------------------------------------------------------------------------
module "api_integrations" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-api-integration.git?ref=feature/TFMOD-0001-feat-initial-module-imple"

  providers = {
    snowflake = snowflake.ingest_object_provisioner
  }

  api_integration_configs = local.api_integrations
}

# ----------------------------------------------------------------------------
# • 2.5 Stages
# ----------------------------------------------------------------------------
module "stage" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-stage.git?ref=v1.2.0"

  providers = {
    snowflake = snowflake.ingest_object_provisioner
  }

  stage_configs = local.stages

  depends_on = [module.storage_integrations]
}

# ----------------------------------------------------------------------------
# • 2.6 Tables
# ----------------------------------------------------------------------------
module "table" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-table.git?ref=v3.0.0"

  providers = {
    snowflake = snowflake.data_object_provisioner
  }

  table_configs = local.tables

  depends_on = [module.stage]
}

# ----------------------------------------------------------------------------
# • 2.7 Table Grants
# Applied under data_object_provisioner so the grantor is the table owner
# (DATA_OBJECT_ADMIN), matching Snowflake's ownership boundary. Workaround
# for terraform-snowflake-table v3.0.0 dropping the `grants` attribute;
# delete this resource once the module applies grants itself.
# ----------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "table_grants" {
  for_each = local.table_grant_pairs

  provider = snowflake.data_object_provisioner

  account_role_name = each.value.role_name
  privileges        = each.value.privileges

  on_schema_object {
    object_type = "TABLE"
    object_name = "\"${each.value.database}\".\"${each.value.schema}\".\"${each.value.name}\""
  }

  depends_on = [module.table]
}

# ============================================================================
# PHASE 3: AWS Trust Policy Reconcile
# ============================================================================
# Reconciles the IAM role's trust policy with the live storage integration's
# STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID on every apply. Values
# come directly from the storage integration module output — no JSON config.
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# • 3.1 Update IAM Role trust policy with Snowflake credentials
# ----------------------------------------------------------------------------
module "aws_iam_role_final" {
  source = "./modules/iam_role_final"

  enabled                = local.has_storage_integration_config
  role_name              = local.iam_role_config.name
  snowflake_iam_user_arn = local.snowflake_iam_user_arn_runtime
  snowflake_external_id  = local.snowflake_external_id_runtime

  depends_on = [module.storage_integrations, module.iam_role]
}


# ============================================================================
# PHASE 4: Snowpipes (BRONZE layer)
# ============================================================================

# ----------------------------------------------------------------------------
# • 4.1 Snowpipe creation
# ----------------------------------------------------------------------------
module "pipe" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-pipe.git?ref=v2.1.0"

  providers = {
    snowflake = snowflake.ingest_object_provisioner
  }

  pipe_configs = var.enable_snowpipe_creation ? local.snowpipes : {}

  depends_on = [
    module.aws_iam_role_final,
    module.table,
    snowflake_grant_privileges_to_account_role.table_grants,
  ]
}

# ----------------------------------------------------------------------------
# • 4.2 S3 Event Notifications for Snowpipe Auto-Ingest
# ----------------------------------------------------------------------------
module "s3_notification" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-aws-s3-bucket.git//modules/event-notification?ref=v1.0.0"

  bucket_name = local.s3_config.bucket_name

  sqs_notifications = [
    for key, pipe_output in module.pipe.pipes : {
      id            = "${lower(replace(local.snowpipes[key].name, "_", "-"))}-notification"
      queue_arn     = pipe_output.notification_channel
      events        = ["s3:ObjectCreated:*"]
      filter_prefix = lookup(local.snowpipes[key], "filter_prefix", null)
      filter_suffix = lookup(local.snowpipes[key], "filter_suffix", null)
    } if lookup(local.snowpipes[key], "auto_ingest", false) == true
  ]

  depends_on = [module.pipe, module.s3]
}

# ============================================================================
# PHASE 5: Dynamic Tables (SILVER layer)
# ============================================================================

# ----------------------------------------------------------------------------
# • 5.1 Dynamic Table Module
# ----------------------------------------------------------------------------
module "dynamic_table" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-dynamic-table.git?ref=v1.1.0"

  providers = {
    snowflake = snowflake.data_object_provisioner
  }

  dynamic_table_configs = local.dynamic_tables_silver

  depends_on = [
    module.database_schemas,
    module.table,
    module.warehouse
  ]
}

# ----------------------------------------------------------------------------
# • 5.2 Dynamic Tables — GOLD layer
#   GOLD dims/facts reference SILVER.CLEAN_NORTHBRIDGE_DT, so SILVER must exist first
# ----------------------------------------------------------------------------
module "dynamic_table_gold" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-dynamic-table.git?ref=v1.1.0"

  providers = {
    snowflake = snowflake.data_object_provisioner
  }

  dynamic_table_configs = local.dynamic_tables_gold

  depends_on = [
    module.dynamic_table
  ]
}

# ============================================================================
# PHASE 6a: Analyst Role (consumed by view grants in 6c)
# ============================================================================
# NORTHBRIDGE_ANALYST is the read-only role granted SELECT on GOLD views.
# Creating it in Terraform removes the manual bootstrap step previously in
# README §2b. Bootstrap requirement: DB_PROVISIONER must hold CREATE ROLE on
# the account — run once as ACCOUNTADMIN:
#
#   GRANT CREATE ROLE ON ACCOUNT TO ROLE DB_PROVISIONER;
#
# DB_PROVISIONER becomes the role's owner and can therefore grant it onward
# (e.g. to SYSADMIN) without further privilege.
# ----------------------------------------------------------------------------
resource "snowflake_account_role" "northbridge_analyst" {
  provider = snowflake.db_provisioner

  name    = "NORTHBRIDGE_ANALYST"
  comment = "[${var.project_code}] Read-only access to GOLD views for dashboard users"
}

resource "snowflake_grant_account_role" "northbridge_analyst_to_sysadmin" {
  provider = snowflake.db_provisioner

  role_name        = snowflake_account_role.northbridge_analyst.name
  parent_role_name = "SYSADMIN"
}

# Warehouse USAGE — granted by warehouse owner (WAREHOUSE_PROVISIONER).
resource "snowflake_grant_privileges_to_account_role" "analyst_warehouse_usage" {
  provider = snowflake.warehouse_provisioner

  account_role_name = snowflake_account_role.northbridge_analyst.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = upper("${var.project_code}_STREAMLIT_WH")
  }

  depends_on = [module.warehouse]
}

# Database USAGE — granted by database owner (DB_PROVISIONER).
resource "snowflake_grant_privileges_to_account_role" "analyst_database_usage" {
  provider = snowflake.db_provisioner

  account_role_name = snowflake_account_role.northbridge_analyst.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = upper("${var.project_code}_NORTHBRIDGE_DATABASE")
  }

  depends_on = [module.database_schemas]
}

# Schema USAGE on GOLD + STREAMLIT — granted by schema owner (DB_PROVISIONER).
resource "snowflake_grant_privileges_to_account_role" "analyst_schema_usage" {
  for_each = toset(["GOLD", "STREAMLIT"])

  provider = snowflake.db_provisioner

  account_role_name = snowflake_account_role.northbridge_analyst.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = "\"${upper("${var.project_code}_NORTHBRIDGE_DATABASE")}\".\"${each.value}\""
  }

  depends_on = [module.database_schemas]
}

# CREATE VIEW on GOLD — granted by schema owner (DB_PROVISIONER) to the
# data_object_provisioner role used by module.views. The schema-grants module
# has no create_view_roles knob, so this issues it directly. Without this,
# `terraform apply` after a destroy fails with "Insufficient privileges to
# operate on schema 'GOLD'" when module.views tries to create the views.
resource "snowflake_grant_privileges_to_account_role" "data_object_create_view" {
  provider = snowflake.db_provisioner

  account_role_name = var.data_object_provisioner_role
  privileges        = ["CREATE VIEW"]

  on_schema {
    schema_name = "\"${upper("${var.project_code}_NORTHBRIDGE_DATABASE")}\".\"GOLD\""
  }

  depends_on = [module.database_schemas]
}

# ============================================================================
# PHASE 6b: Views (GOLD layer)
# ============================================================================
# Views read from GOLD CUST360_* dynamic tables, so they must be created after
# module.dynamic_table_gold. The view module does not apply grants, so grants
# are issued separately below via snowflake_grant_privileges_to_account_role
# (same workaround pattern as table_grants).
# ----------------------------------------------------------------------------
module "views" {
  source = "git::https://github.com/subhamay-bhattacharyya-tf/terraform-snowflake-view.git?ref=feature/TFMOD-0007-feat-initial-module-imple"

  providers = {
    snowflake = snowflake.data_object_provisioner
  }

  views = {
    for k, v in local.views : k => {
      name      = v.name
      database  = v.database
      schema    = v.schema
      statement = v.statement
      is_secure = v.is_secure
      comment   = v.comment
    }
  }

  depends_on = [
    module.dynamic_table_gold,
    snowflake_grant_privileges_to_account_role.data_object_create_view,
  ]
}

# ============================================================================
# PHASE 6c: View grants
# ============================================================================
# Per-view SELECT grants to the roles named in the JSON `grants[]` block
# (currently NORTHBRIDGE_ANALYST). The view module does not apply grants
# itself, so this resource issues them directly under the view owner alias.
# ----------------------------------------------------------------------------
resource "snowflake_grant_privileges_to_account_role" "view_grants" {
  for_each = local.view_grant_pairs

  provider = snowflake.data_object_provisioner

  account_role_name = each.value.role_name
  privileges        = each.value.privileges

  on_schema_object {
    object_type = "VIEW"
    object_name = "\"${each.value.database}\".\"${each.value.schema}\".\"${each.value.name}\""
  }

  depends_on = [
    module.views,
    snowflake_account_role.northbridge_analyst,
  ]
}