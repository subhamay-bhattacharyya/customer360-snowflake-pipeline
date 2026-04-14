---
name: snowflake-config-stages-fileformats
description: >
  Use this skill whenever writing, editing, or validating the `stages` or
  `file_formats` blocks inside `infra/platform/tf/config/snowflake/config.json` for the
  Customer 360 / NorthBridge Snowflake pipeline. Trigger when the user wants
  to: add an external S3 stage or internal stage; configure a JSON file format
  with parsing options (strip_outer_array, compression, allow_duplicate, etc.);
  wire a stage to a storage integration; set directory listing on an internal
  stage; reference a file format from a stage; or debug a Terraform apply
  failure on snowflake_stage or snowflake_file_format resources. Also trigger
  when the user asks how to connect Snowflake to S3 via a stage, or wants to
  validate an existing stage/file_format config block.
---

# Snowflake Config — Stages & File Formats

This skill governs the `stages` and `file_formats` blocks nested inside
`databases.*.schemas[]` in `infra/platform/tf/config/snowflake/config.json`. Both blocks
are consumed by `module.stage` and `module.file_formats` in `main.tf`.

---

## File Formats — JSON Schema

```json
"file_formats": {
  "<logical_key>": {
    "name":               "<string, required — UPPER_SNAKE_CASE>",
    "database":           "<string, required>",
    "schema":             "<string, required>",
    "type":               "<JSON | CSV | PARQUET | AVRO | ORC | XML>",
    "comment":            "<string, optional>",

    "compression":        "<AUTO | GZIP | BZ2 | BROTLI | ZSTD | DEFLATE | RAW_DEFLATE | NONE>",
    "enable_octal":       "<bool, default false>",
    "allow_duplicate":    "<bool, default false>",
    "strip_outer_array":  "<bool, default false — set true for arrays of records>",
    "strip_null_values":  "<bool, default false>",
    "ignore_utf8_errors": "<bool, default false>",
    "skip_byte_order_mark": "<bool, default false>"
  }
}
```

### Key JSON options explained

| Option | When to set `true` |
|---|---|
| `strip_outer_array` | Source JSON is `[{...}, {...}]` — strips the outer `[]` so each object loads as one row |
| `allow_duplicate` | Source JSON has duplicate keys — last value wins |
| `strip_null_values` | Omit null fields from the VARIANT rather than storing them as null |
| `ignore_utf8_errors` | Source files may contain invalid UTF-8 byte sequences |

> For the NorthBridge pipeline the source files are newline-delimited JSON objects
> (not arrays), so `strip_outer_array` should be `false`.

---

## Stages — JSON Schema

```json
"stages": {
  "<logical_key>": {
    "name":                "<string, required — UPPER_SNAKE_CASE>",
    "database":            "<string, required>",
    "schema":              "<string, required>",
    "stage_type":          "<external | internal, required>",
    "comment":             "<string, optional>",

    "file_format":         "<file_format_name, optional — reference by name>",

    "url":                 "<s3://bucket/prefix/ — required for external>",
    "storage_integration": "<INTEGRATION_NAME — required for external>",

    "directory_enabled":   "<bool, default false — internal stages only>"
  }
}
```

### Stage type rules

| Field | External (S3) | Internal |
|---|---|---|
| `url` | ✅ Required | ❌ Not used |
| `storage_integration` | ✅ Required | ❌ Not used |
| `directory_enabled` | ❌ | ✅ Set `true` to enable `LIST @stage` |
| `file_format` | ✅ Recommended | ✅ Recommended |

> The `storage_integration` value must exactly match the `name` field of a
> `storage_integrations` entry in the same config. Terraform resolves this
> at plan time — a mismatch causes a `InvalidStorageIntegration` error.

---

## NorthBridge Pipeline — Standard Patterns

### JSON file format (`BRONZE.JSON_FILE_FORMAT`)

```json
"file_formats": {
  "json_file_format": {
    "name":               "JSON_FILE_FORMAT",
    "database":           "NORTHBRIDGE_DATABASE",
    "schema":             "BRONZE",
    "type":               "JSON",
    "compression":        "AUTO",
    "enable_octal":       false,
    "allow_duplicate":    false,
    "strip_outer_array":  false,
    "strip_null_values":  false,
    "ignore_utf8_errors": false,
    "comment":            "JSON parsing config for NorthBridge raw ingestion"
  }
}
```

### External S3 stage (`BRONZE.RAW_EXTERNAL_STG`)

```json
"stages": {
  "raw_external_stg": {
    "name":                "RAW_EXTERNAL_STG",
    "database":            "NORTHBRIDGE_DATABASE",
    "schema":              "BRONZE",
    "stage_type":          "external",
    "url":                 "s3://northbridge-raw-data/raw-data/json/",
    "storage_integration": "S3_STORAGE_INTEGRATION",
    "file_format":         "JSON_FILE_FORMAT",
    "comment":             "External S3 stage for NorthBridge raw JSON ingestion"
  }
}
```

### Internal stage (`BRONZE.RAW_INTERNAL_STG`)

```json
"stages": {
  "raw_internal_stg": {
    "name":               "RAW_INTERNAL_STG",
    "database":           "NORTHBRIDGE_DATABASE",
    "schema":             "BRONZE",
    "stage_type":         "internal",
    "file_format":        "JSON_FILE_FORMAT",
    "directory_enabled":  true,
    "comment":            "Internal stage for temporary file processing"
  }
}
```

---

## Dependency Order

Terraform must create objects in this order — enforced by `depends_on` in `main.tf`:

```
storage_integration  →  stage (external)
file_format          →  stage (either type)
database + schema    →  file_format, stage
```

**Never define a stage in the config before its `storage_integration` and
`file_format` entries.** Although Terraform handles the `depends_on` chain,
the config JSON must reference valid names or `terraform plan` will fail
with a lookup error in `locals.tf`.

---

## Common Mistakes

- **Missing `storage_integration` on external stage** — Snowflake will reject the stage creation with `IntegrationNotFound`.
- **Using an internal stage for Snowpipe auto-ingest** — Snowpipe auto-ingest requires an external stage backed by S3 + SQS; internal stages only work with manual `COPY INTO`.
- **`url` without trailing slash** — Snowflake treats `s3://bucket/prefix` (no slash) as a single object path, not a prefix. Always add `/` at the end.
- **Referencing `file_format` by logical key instead of `name`** — the stage's `file_format` field must contain the Snowflake object name (e.g. `JSON_FILE_FORMAT`), not the JSON map key (e.g. `json_file_format`).
- **Setting `strip_outer_array: true` for newline-delimited JSON** — only set this if your source files wrap all records in a top-level `[...]` array.