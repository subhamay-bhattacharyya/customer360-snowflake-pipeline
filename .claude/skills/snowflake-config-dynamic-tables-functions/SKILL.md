---
name: snowflake-config-dynamic-tables-functions
description: >
  Use this skill whenever writing, editing, or validating the `dynamic_tables`
  or `functions` blocks inside `input-jsons/snowflake/config.json` for the
  Customer 360 / NorthBridge Snowflake pipeline. Trigger when the user wants
  to: add or configure a dynamic table (CLEAN_NORTHBRIDGE_DT) in the SILVER
  schema; set target_lag and warehouse for a dynamic table; reference a SQL
  template file for a dynamic table query; define a GOLD-layer UDF
  (PROMINENT_INDEX, THREE_SUB_INDEX_CRITERIA, GET_INT); understand the
  difference between downstream and fixed target_lag; or debug a Terraform
  apply failure on snowflake_dynamic_table or snowflake_function resources.
  Also trigger when the user asks how to auto-refresh the SILVER layer or
  how to register a scalar UDF in the GOLD schema.
---

# Snowflake Config — Dynamic Tables & Functions

This skill governs the `dynamic_tables` and `functions` blocks nested inside
`databases.*.schemas[]` in `input-jsons/snowflake/config.json`. These are
consumed by `module.dynamic_table` (Phase 5) in `main.tf`.

---

## Dynamic Tables — JSON Schema

```json
"dynamic_tables": {
  "<logical_key>": {
    "name":                "<string, required — UPPER_SNAKE_CASE>",
    "database":            "<string, required>",
    "schema":              "<string, required>",
    "warehouse":           "<WAREHOUSE_NAME, required>",
    "target_lag":          "<'downstream' | 'n seconds' | 'n minutes' | 'n hours' | 'n days'>",
    "query_template_file": "<relative path to .tpl file, required>",
    "comment":             "<string, optional>",

    "refresh_mode":        "<AUTO | FULL | INCREMENTAL, default AUTO>",
    "initialize":          "<ON_CREATE | ON_SCHEDULE, default ON_CREATE>",
    "or_replace":          "<bool, default false>",
    "grants": [
      {
        "role_name":  "<ROLE_NAME>",
        "privileges": ["SELECT"]
      }
    ]
  }
}
```

### `target_lag` values

| Value | Behaviour | When to use |
|---|---|---|
| `"downstream"` | Refreshes only when a downstream dynamic table or task requests data | SILVER tables feeding GOLD dynamic tables |
| `"1 minutes"` | Refreshes every 1 minute regardless of demand | Near-real-time dashboards |
| `"1 hours"` | Refreshes every hour | Batch analytics |

> For the NorthBridge pipeline, `CLEAN_NORTHBRIDGE_DT` uses `"downstream"` so
> it only materialises when a GOLD object requests it, avoiding unnecessary
> compute costs.

### `refresh_mode` values

| Value | Behaviour |
|---|---|
| `AUTO` | Snowflake decides incremental or full refresh — recommended default |
| `FULL` | Always full re-scan of the base table — use when incremental is not supported |
| `INCREMENTAL` | Only process new/changed rows — requires the query to be incrementally composable |

---

## Functions (UDFs) — JSON Schema

```json
"functions": {
  "<logical_key>": {
    "name":      "<string, required — UPPER_SNAKE_CASE>",
    "database":  "<string, required>",
    "schema":    "<string, required>",
    "comment":   "<string, optional>",

    "language":  "<JAVASCRIPT | PYTHON | SQL | JAVA | SCALA, default SQL>",
    "return_type": "<Snowflake type, required>",
    "arguments": [
      { "name": "<arg_name>", "type": "<Snowflake type>" }
    ],
    "body_template_file": "<relative path to .tpl file — omit for inline>",
    "body":               "<inline function body — omit if using template file>",
    "is_secure":          "<bool, default false>",
    "grants": [
      { "role_name": "<ROLE_NAME>", "privileges": ["USAGE"] }
    ]
  }
}
```

> Functions are defined in the GOLD schema. Grant `USAGE` to
> `NORTHBRIDGE_ANALYST` so the dashboard can call them.

---

## NorthBridge Pipeline — Standard Patterns

### SILVER dynamic table (`SILVER.CLEAN_NORTHBRIDGE_DT`)

```json
"dynamic_tables": {
  "clean_northbridge_dt": {
    "name":                "CLEAN_NORTHBRIDGE_DT",
    "database":            "NORTHBRIDGE_DATABASE",
    "schema":              "SILVER",
    "warehouse":           "LOAD_WH",
    "target_lag":          "downstream",
    "refresh_mode":        "AUTO",
    "initialize":          "ON_CREATE",
    "query_template_file": "templates/dynamic-tables/clean_northbridge.tpl",
    "comment":             "Cleansed and typed NorthBridge dataset — auto-refreshed from BRONZE",
    "grants": [
      { "role_name": "NORTHBRIDGE_ANALYST", "privileges": ["SELECT"] }
    ]
  }
}
```

### GOLD UDFs

```json
"functions": {
  "prominent_index": {
    "name":     "PROMINENT_INDEX",
    "database": "NORTHBRIDGE_DATABASE",
    "schema":   "GOLD",
    "language": "JAVASCRIPT",
    "return_type": "VARCHAR",
    "arguments": [
      { "name": "credit_score", "type": "NUMBER" },
      { "name": "risk_rating",  "type": "VARCHAR" }
    ],
    "body_template_file": "templates/functions/prominent_index.tpl",
    "comment": "Returns the dominant customer risk index",
    "grants": [
      { "role_name": "NORTHBRIDGE_ANALYST", "privileges": ["USAGE"] }
    ]
  },
  "three_sub_index_criteria": {
    "name":     "THREE_SUB_INDEX_CRITERIA",
    "database": "NORTHBRIDGE_DATABASE",
    "schema":   "GOLD",
    "language": "SQL",
    "return_type": "BOOLEAN",
    "arguments": [
      { "name": "income_tier",  "type": "VARCHAR" },
      { "name": "credit_tier",  "type": "VARCHAR" },
      { "name": "kyc_status",   "type": "VARCHAR" }
    ],
    "body_template_file": "templates/functions/three_sub_index_criteria.tpl",
    "comment": "Customer scoring evaluation logic — returns true if 3 sub-criteria met"
  },
  "get_int": {
    "name":        "GET_INT",
    "database":    "NORTHBRIDGE_DATABASE",
    "schema":      "GOLD",
    "language":    "SQL",
    "return_type": "NUMBER",
    "arguments": [
      { "name": "val", "type": "VARIANT" }
    ],
    "body": "SELECT val::NUMBER",
    "comment": "Helper — safely casts VARIANT to NUMBER"
  }
}
```

---

## Template File Convention

Dynamic table SQL templates live in `infra/platform/tf/templates/dynamic-tables/`.
Function body templates live in `infra/platform/tf/templates/functions/`.

The `query_template_file` and `body_template_file` paths are relative to
`infra/platform/tf/` (the Terraform working directory). Always use forward
slashes regardless of OS.

---

## Dependency Order

```
BRONZE.RAW_NORTHBRIDGE (table)   +   LOAD_WH (warehouse)
              │
              ▼  dynamic table query references
SILVER.CLEAN_NORTHBRIDGE_DT
              │
              ▼  downstream lag triggers
GOLD.* dynamic tables / views
              │
              ▼  called from views/queries
GOLD.PROMINENT_INDEX, GOLD.THREE_SUB_INDEX_CRITERIA, GOLD.GET_INT
```

`module.dynamic_table` has `depends_on` = `[module.database_schemas, module.table, module.warehouse]`
in `main.tf`. Do not create a dynamic table config entry that references a
table or warehouse not yet defined in the config.

---

## Common Mistakes

- **Using `target_lag: "downstream"` on the outermost dynamic table** — `downstream` only works when a downstream object exists that pulls from it. If nothing downstream exists yet, Snowflake will never refresh it. Use a fixed lag (e.g. `"5 minutes"`) during initial development, then switch to `downstream` once GOLD objects are defined.
- **`query_template_file` path starting with `./`** — use `templates/...` not `./templates/...`; the leading `./` causes `templatefile()` to fail with a file-not-found error.
- **Defining a function without `return_type`** — required by the Snowflake provider; Terraform will error at plan time.
- **Granting `SELECT` instead of `USAGE` on functions** — functions require `USAGE` privilege, not `SELECT`. Using `SELECT` causes a grant error.
- **`body` and `body_template_file` both set** — mutually exclusive; use one or the other.