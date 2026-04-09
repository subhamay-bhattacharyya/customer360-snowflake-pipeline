# -- infra/snowflake/tf/versions.tf
# ============================================================================
# Required Providers
# ============================================================================
# NOTE: This tells Terraform to use snowflakedb/snowflake, not hashicorp/snowflake
# ============================================================================

terraform {
  required_version = ">= 1.14.1"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = ">= 1.0.0"
    }
  }
}