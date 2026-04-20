# -- infra/platform/tf/validations.tf
# ============================================================================
# Config assertions — fail plan early when required conventions are violated.
# ============================================================================
# locals.tf renders SQL templates via `templatefile()` and prepends a fixed
# directory prefix to each referenced filename:
#
#   - snowpipes[].copy_template        → templates/snowpipe-copy-statements/<file>
#   - dynamic_tables[].query_template  → templates/dynamic-tables/<file>
#
# If the config JSON value contains that prefix as well, the rendered path
# doubles up (e.g. templates/dynamic-tables/templates/dynamic-tables/file.tpl)
# and `terraform plan` fails with a cryptic templatefile() error. Guard against
# that regression by asserting values are filenames only (no `/`).
# ============================================================================

resource "terraform_data" "validate_template_paths" {
  lifecycle {
    precondition {
      condition = alltrue(flatten([
        for db_key, db in lookup(local.snowflake_config, "databases", {}) : [
          for schema in lookup(db, "schemas", []) : concat(
            [
              for pipe_key, pipe in lookup(schema, "snowpipes", {}) :
              !can(regex("/", lookup(pipe, "copy_template", "")))
            ],
            [
              for dt_key, dt in lookup(schema, "dynamic_tables", {}) :
              !can(regex("/", lookup(dt, "query_template_file", "")))
            ]
          )
        ]
      ]))
      error_message = <<-EOT
        Invalid template path in Snowflake config JSON.

        Fields `copy_template` (under snowpipes) and `query_template_file`
        (under dynamic_tables) must be filenames only, e.g.:

            "query_template_file": "clean_northbridge.tpl"

        Not:

            "query_template_file": "templates/dynamic-tables/clean_northbridge.tpl"

        locals.tf prepends the directory prefix automatically when rendering
        the template.
      EOT
    }
  }
}
