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

# ============================================================================
# PHASE 3: AWS Trust Policy Update
# ============================================================================
# Updates the IAM role trust policy with Snowflake credentials from storage integration.
#
# WORKFLOW FOR FRESH DEPLOYMENTS:
# 1. First apply:  terraform apply -var="enable_trust_policy_update=false"
#    - Creates all resources with placeholder trust policy
# 2. Second apply: terraform apply -var="enable_trust_policy_update=true"
#    - Updates trust policy with Snowflake values
# 3. Update config/aws/{env}/config.json with the Snowflake values from output
# 4. Future applies: terraform apply (no flag needed, uses JSON config values)
# ----------------------------------------------------------------------------

# ----------------------------------------------------------------------------
# • 3.1 Update IAM Role trust policy with Snowflake credentials
# ----------------------------------------------------------------------------
module "aws_iam_role_final" {
  source = "./modules/iam_role_final"

  enabled                = var.enable_trust_policy_update && local.has_storage_integration_config
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
    module.table
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