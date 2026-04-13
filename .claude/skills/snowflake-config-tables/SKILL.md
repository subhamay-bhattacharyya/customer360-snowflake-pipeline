---
name: snowflake-config-tables
description: >
  Use this skill whenever writing, editing, or validating the `tables` block
  inside `input-jsons/snowflake/config.json` for the Customer 360 / NorthBridge
  Snowflake pipeline. Trigger when the user wants to: add a new table to the
  config JSON; define columns with types, nullability, autoincrement, or
  defaults; set a primary key; choose between TRANSIENT and PERMANENT table
  types; add audit columns (_STG_FILE_NAME, _STG_FILE_LOAD_TS, _STG_FILE_MD5,
  _COPY_DATA_TS); or understand why a Terraform apply is failing on a
  snowflake_table resource. Also trigger when the user pastes a table config
  and asks to extend, fix, or validate it. This skill covers BRONZE RAW tables,
  SILVER typed tables, and GOLD dimension/fact tables.
---

# Snowflake Config — Tables

This skill governs the `databases.*.schemas[].tables` block in
`input-jsons/snowflake/config.json`. Every table consumed by
`module.table` in `main.tf` must be defined here.

---

## JSON Schema

```json
"tables": {
  "<logical_key>": {
    "database":           "<string, required>",
    "schema":             "<string, required>",
    "name":               "<string, required — UPPER_SNAKE_CASE>",
    "table_type":         "<TRANSIENT | PERMANENT | TEMPORARY, default PERMANENT>",
    "drop_before_create": "<bool, default false>",
    "comment":            "<string, optional>",
    "data_retention_time_in_days": "<0–90, default 1>",
    "change_tracking":    "<bool, default false>",
    "cluster_by":         ["<col1>", "<col2>"],
    "columns": [
      {
        "name":     "<UPPER_SNAKE_CASE, required>",
        "type":     "<Snowflake type, required>",
        "nullable": "<bool, default true>",
        "comment":  "<string, optional>",
        "default":  "<literal string, optional — wrap string literals in inner single quotes>",
        "autoincrement": {
          "start":     "<number, default 1>",
          "increment": "<number, default 1>",
          "order":     "<bool, default false>"
        }
      }
    ],
    "primary_key": {
      "name": "<optional constraint name>",
      "keys": ["<col1>"]
    },
    "grants": [
      {
        "role_name":  "<ROLE_NAME>",
        "privileges": ["SELECT"]
      }
    ]
  }
}
```

---

## Required vs Optional Fields

| Field | Required | Notes |
|---|---|---|
| `database` | ✅ | Must match a database defined in the same config |
| `schema` | ✅ | Must match a schema defined under that database |
| `name` | ✅ | UPPER_SNAKE_CASE; used as the Terraform resource key |
| `columns` | ✅ | At least one entry |
| `table_type` | ❌ | Default `PERMANENT`; use `TRANSIENT` for BRONZE/SILVER |
| `drop_before_create` | ❌ | Default `false`; set `true` only for idempotent dev deploys |
| `data_retention_time_in_days` | ❌ | `0` for TRANSIENT; `7` for GOLD PERMANENT tables |
| `primary_key` | ❌ | Required for BRONZE RAW table (`ID` column) |
| `grants` | ❌ | Add `SELECT` for `NORTHBRIDGE_ANALYST` on GOLD tables |

---

## Column Type Quick Reference

| Category | Types |
|---|---|
| Integer / Numeric | `NUMBER(38,0)`, `NUMBER(8,2)`, `INT`, `FLOAT`, `DOUBLE` |
| String | `VARCHAR(n)`, `STRING`, `TEXT`, `CHAR(n)` |
| Date / Time | `DATE`, `TIMESTAMP_NTZ`, `TIMESTAMP_LTZ`, `TIMESTAMP_TZ` |
| Boolean | `BOOLEAN` |
| Semi-structured | `VARIANT`, `OBJECT`, `ARRAY` |
| Binary | `BINARY`, `VARBINARY` |

> Use `TIMESTAMP_NTZ` for all audit and pipeline timestamps.
> Use `VARCHAR(500)` for file path columns.
> Use `VARCHAR(32)` for MD5 hash columns.

---

## Table Type Guidance

| Type | Fail-safe | Time Travel | When to use |
|---|---|---|---|
| `TRANSIENT` | ❌ | 0 or 1 day | BRONZE `RAW_*` tables, SILVER typed tables |
| `PERMANENT` | ✅ | Up to 90 days | GOLD DIM_*, FACT_* tables |
| `TEMPORARY` | ❌ | 0 or 1 day | Session-scoped scratch — never in config.json |

---

## Autoincrement Rules

- Only valid on `NUMBER` or `INT` columns.
- `autoincrement` and `default` are **mutually exclusive** on the same column.
- Always set `nullable: false` on autoincrement columns.

---

## NorthBridge Pipeline — Standard Table Patterns

### BRONZE RAW table (`BRONZE.RAW_NORTHBRIDGE`)

```json
"raw_northbridge": {
  "database": "NORTHBRIDGE_DATABASE",
  "schema": "BRONZE",
  "name": "RAW_NORTHBRIDGE",
  "table_type": "TRANSIENT",
  "drop_before_create": true,
  "data_retention_time_in_days": 1,
  "comment": "Raw ingestion table — VARIANT payload + audit columns",
  "columns": [
    {
      "name": "ID", "type": "NUMBER(38,0)", "nullable": false,
      "comment": "Surrogate PK",
      "autoincrement": { "start": 1, "increment": 1, "order": false }
    },
    { "name": "INDEX_RECORD_TS", "type": "TIMESTAMP_NTZ", "nullable": false,
      "comment": "Record timestamp from source" },
    { "name": "JSON_DATA", "type": "VARIANT", "nullable": false,
      "comment": "Raw JSON payload" },
    { "name": "RECORD_COUNT", "type": "NUMBER(38,0)", "nullable": false },
    { "name": "JSON_VERSION", "type": "VARCHAR(255)", "nullable": false },
    { "name": "_STG_FILE_NAME",    "type": "VARCHAR(500)", "nullable": true,
      "comment": "Audit — source stage file name" },
    { "name": "_STG_FILE_LOAD_TS", "type": "TIMESTAMP_NTZ", "nullable": true,
      "comment": "Audit — stage load timestamp" },
    { "name": "_STG_FILE_MD5",     "type": "VARCHAR(32)", "nullable": true,
      "comment": "Audit — MD5 hash of stage file" },
    { "name": "_COPY_DATA_TS",     "type": "TIMESTAMP_NTZ", "nullable": true,
      "comment": "Audit — COPY INTO execution timestamp" }
  ],
  "primary_key": { "keys": ["ID"] }
}
```

### GOLD PERMANENT table (example: `GOLD.DIM_CUSTOMER`)

```json
"dim_customer": {
  "database": "NORTHBRIDGE_DATABASE",
  "schema": "GOLD",
  "name": "DIM_CUSTOMER",
  "table_type": "PERMANENT",
  "data_retention_time_in_days": 7,
  "comment": "Customer dimension — typed, bucketed, enriched",
  "columns": [
    { "name": "CUSTOMER_ID",   "type": "VARCHAR(20)",  "nullable": false },
    { "name": "FULL_NAME",     "type": "VARCHAR(100)", "nullable": true  },
    { "name": "ANNUAL_INCOME", "type": "FLOAT",        "nullable": true  },
    { "name": "CREDIT_SCORE",  "type": "NUMBER(38,0)", "nullable": true  },
    { "name": "INCOME_TIER",   "type": "VARCHAR(30)",  "nullable": true  },
    { "name": "CREDIT_TIER",   "type": "VARCHAR(30)",  "nullable": true  },
    { "name": "RISK_RATING",   "type": "VARCHAR(10)",  "nullable": true  },
    { "name": "DW_INSERT_TS",  "type": "TIMESTAMP_NTZ","nullable": true  }
  ],
  "grants": [
    { "role_name": "NORTHBRIDGE_ANALYST", "privileges": ["SELECT"] }
  ]
}
```

---

## Common Mistakes

- **Using `PERMANENT` for BRONZE/SILVER** — always use `TRANSIENT` to avoid fail-safe storage costs on raw/staging data.
- **Omitting `database` and `schema`** — both are required; the Terraform module uses them to scope the resource.
- **`default` on an autoincrement column** — mutually exclusive; Terraform will error at plan time.
- **Lowercase column names** — Snowflake stores unquoted identifiers in UPPERCASE; always use `UPPER_SNAKE_CASE` in the config to avoid case-sensitivity issues.
- **Missing audit columns on BRONZE table** — `_STG_FILE_NAME`, `_STG_FILE_LOAD_TS`, `_STG_FILE_MD5`, `_COPY_DATA_TS` must all be present for the Snowpipe COPY statement to succeed.