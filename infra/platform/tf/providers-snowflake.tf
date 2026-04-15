# -- infra/platform/tf/providers-snowflake.tf (Platform Module)
# ============================================================================
# Snowflake Provider Configuration
# ============================================================================
# Authentication: Uses JWT with RSA private key passed as a Terraform variable.
# The key body (no PEM headers, no newlines) is stored in HCP Terraform as a
# sensitive Terraform variable. PEM format is reconstructed at plan time.
#
# Required variables (set in HCP Terraform Variable Set):
#   - snowflake_private_key          (Terraform variable, sensitive)
#   - TF_VAR_snowflake_organization_name (env var)
#   - TF_VAR_snowflake_account_name      (env var)
#   - TF_VAR_snowflake_user              (env var)
#
# Provider Aliases:
#   - default (db_provisioner_role)    : Database/Schema creation
#   - warehouse_provisioner            : Warehouse creation
#   - data_object_provisioner          : File formats, tables
#   - ingest_object_provisioner        : Storage integrations, stages, pipes
# ============================================================================

# Default provider - uses db_provisioner_role for database/schema operations
provider "snowflake" {
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  private_key       = base64decode(replace(var.snowflake_private_key, "/[\\s]+/", ""))
  authenticator     = "SNOWFLAKE_JWT"
  role              = var.db_provisioner_role != "" ? var.db_provisioner_role : null
  warehouse         = var.snowflake_warehouse != "" ? var.snowflake_warehouse : null

  params = {
    query_tag = "${var.project_code}-terraform-db-provisioner"
  }

  preview_features_enabled = [
    "snowflake_file_format_resource",
    "snowflake_storage_integration_aws_resource",
    "snowflake_stage_internal_resource",
    "snowflake_stage_external_s3_resource",
    "snowflake_pipe_resource",
    "snowflake_dynamic_table_resource"
  ]
}

# Alias for db_provisioner (same as default, for explicit module references)
provider "snowflake" {
  alias             = "db_provisioner"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  private_key       = base64decode(replace(var.snowflake_private_key, "/[\\s]+/", ""))
  authenticator     = "SNOWFLAKE_JWT"
  role              = var.db_provisioner_role != "" ? var.db_provisioner_role : null
  warehouse         = var.snowflake_warehouse != "" ? var.snowflake_warehouse : null

  params = {
    query_tag = "${var.project_code}-terraform-db-provisioner"
  }

  preview_features_enabled = [
    "snowflake_file_format_resource",
    "snowflake_storage_integration_aws_resource",
    "snowflake_stage_internal_resource",
    "snowflake_stage_external_s3_resource",
    "snowflake_pipe_resource",
    "snowflake_dynamic_table_resource"
  ]
}

provider "snowflake" {
  alias             = "warehouse_provisioner"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  private_key       = base64decode(replace(var.snowflake_private_key, "/[\\s]+/", ""))
  authenticator     = "SNOWFLAKE_JWT"
  role              = var.warehouse_provisioner_role != "" ? var.warehouse_provisioner_role : null
  warehouse         = var.snowflake_warehouse != "" ? var.snowflake_warehouse : null

  params = {
    query_tag = "${var.project_code}-terraform-warehouse-provisioner"
  }

  preview_features_enabled = [
    "snowflake_file_format_resource",
    "snowflake_storage_integration_aws_resource",
    "snowflake_stage_internal_resource",
    "snowflake_stage_external_s3_resource"
  ]
}

provider "snowflake" {
  alias             = "data_object_provisioner"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  private_key       = base64decode(replace(var.snowflake_private_key, "/[\\s]+/", ""))
  authenticator     = "SNOWFLAKE_JWT"
  role              = var.data_object_provisioner_role != "" ? var.data_object_provisioner_role : null
  warehouse         = var.snowflake_warehouse != "" ? var.snowflake_warehouse : null

  params = {
    query_tag = "${var.project_code}-terraform-data-object-provisioner"
  }

  preview_features_enabled = [
    "snowflake_file_format_resource",
    "snowflake_storage_integration_aws_resource",
    "snowflake_stage_internal_resource",
    "snowflake_stage_external_s3_resource",
    "snowflake_pipe_resource",
    "snowflake_dynamic_table_resource"
  ]
}

provider "snowflake" {
  alias             = "ingest_object_provisioner"
  organization_name = var.snowflake_organization_name
  account_name      = var.snowflake_account_name
  user              = var.snowflake_user
  private_key       = base64decode(replace(var.snowflake_private_key, "/[\\s]+/", ""))
  authenticator     = "SNOWFLAKE_JWT"
  role              = var.ingest_object_provisioner_role != "" ? var.ingest_object_provisioner_role : null
  warehouse         = var.snowflake_warehouse != "" ? var.snowflake_warehouse : null

  params = {
    query_tag = "${var.project_code}-terraform-ingest-object-provisioner"
  }

  preview_features_enabled = [
    "snowflake_file_format_resource",
    "snowflake_storage_integration_aws_resource",
    "snowflake_stage_internal_resource",
    "snowflake_stage_external_s3_resource",
    "snowflake_pipe_resource"
  ]
}
