# -- infra/platform/tf/backend.tf (Platform Module)
# ============================================================================
# Terraform Backend Configuration
# ============================================================================

terraform {
  cloud {

    organization = "subhamay-snowflake-projects"

    workspaces {
      name = "customer360-snowflake-pipeline"
    }
  }
}