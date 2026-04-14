# -- infra/platform/tf/terraform.tfvars (Platform Module)
# ============================================================================
# Terraform Variable Values
# ============================================================================

# ----------------------------------------------------------------------------
# Snowflake Provider Configuration
# ----------------------------------------------------------------------------
db_provisioner_role            = "PLATFORM_DB_OWNER"
warehouse_provisioner_role     = "WAREHOUSE_ADMIN"
data_object_provisioner_role   = "DATA_OBJECT_ADMIN"
ingest_object_provisioner_role = "INGEST_ADMIN"
snowflake_warehouse            = "UTIL_WH"
# For CI/CD: Set SNOWFLAKE_PRIVATE_KEY environment variable with key content
aws_config_path                = "config/aws/prod/config.json"
snowflake_config_path          = "config/snowflake/prod/config.json"
# ----------------------------------------------------------------------------
# Project Configuration
# AWS(AWS) - Snowflake (SF) - End to End (E2E)
# ----------------------------------------------------------------------------
project_code = "cust360"