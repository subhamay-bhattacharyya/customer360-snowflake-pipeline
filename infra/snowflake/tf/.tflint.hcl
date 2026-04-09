# -- infra/snowflake/tf/.tflint.hcl
# ============================================================================
# TFLint Configuration
# ============================================================================

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Disable module pinned source rule - using main branch for internal modules
rule "terraform_module_pinned_source" {
  enabled = false
}
