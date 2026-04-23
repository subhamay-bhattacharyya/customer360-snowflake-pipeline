---
name: snowflake-config-snowpipes
description: >
  Use this skill whenever writing, editing, or validating the `snowpipes`
  block inside `infra/platform/tf/config/snowflake/config.json` for the
  Customer 360 / NorthBridge Snowflake pipeline. Trigger when the user
  wants to: configure a Snowpipe for auto-ingest from S3; wire the
  Snowpipe COPY statement to a template file; set `auto_ingest: true`
  and understand the SQS notification dependency; add `filter_prefix`
  or `filter_suffix` to scope which S3 objects trigger ingestion; or
  debug why files dropped into S3 are not landing in BRONZE. Also
  trigger when the user asks about `RAW_NORTHBRIDGE_PIPE` in the
  context of this pipeline. Streams and tasks are NOT used in this
  pipeline — ingestion is Snowpipe-driven and downstream refresh is
  handled by Dynamic Tables (`target_lag = "downstream"`).
---

# Snowflake Config — Snowpipes

This skill governs the `snowpipes` block nested inside
`databases.*.schemas[]` in `infra/platform/tf/config/snowflake/config.json`.
Snowpipe is the only ingestion mechanism in this pipeline — there are no
streams or tasks.

---

## Snowpipes — JSON Schema

```json
"snowpipes": {
  "<logical_key>": {
    "name":          "<string, required — UPPER_SNAKE_CASE>",
    "database":      "<string, required>",
    "schema":        "<string, required>",
    "table":         "<target_table_name, required>",
    "stage":         "<stage_name, required>",
    "file_format":   "<file_format_name, required>",
    "copy_template": "<filename under templates/snowpipe-copy-statements/, required>",
    "auto_ingest":   "<bool, default false>",
    "comment":       "<string, optional>",

    "filter_prefix": "<S3 prefix filter, optional>",
    "filter_suffix": "<file extension filter, optional — e.g. '.json'>"
  }
}
```

---

## `auto_ingest` and the SQS dependency

When `auto_ingest: true`, Snowflake provisions an SQS queue channel on
the pipe. `main.tf` reads `module.pipe.pipes[*].notification_channel`
and wires it into `module.s3_notification`, which attaches an
`s3:ObjectCreated:*` event notification on the bucket scoped by
`filter_prefix` / `filter_suffix`.

Snowpipe creation is gated by `var.enable_snowpipe_creation`:

- **First apply** — set `enable_snowpipe_creation=false` so the IAM
  trust reconcile (`module.aws_iam_role_final`) finishes before the
  pipe + S3 notification race against it.
- **Subsequent applies** — leave the variable at its default (`true`).
  The pipe and S3 notification get created, and the trust reconcile
  is idempotent.

---

## NorthBridge Pipeline — Standard Pattern

```json
"snowpipes": {
  "raw_northbridge_pipe": {
    "name":          "RAW_NORTHBRIDGE_PIPE",
    "database":      "NORTHBRIDGE_DATABASE",
    "schema":        "BRONZE",
    "table":         "RAW_NORTHBRIDGE",
    "stage":         "RAW_EXTERNAL_STG",
    "file_format":   "JSON_FILE_FORMAT",
    "copy_template": "raw_northbridge_copy.tpl",
    "auto_ingest":   true,
    "filter_suffix": ".json",
    "comment":       "Auto-ingest pipe — S3 → BRONZE.RAW_NORTHBRIDGE"
  }
}
```

The COPY template lives at
`infra/platform/tf/templates/snowpipe-copy-statements/raw_northbridge_copy.tpl`.
`locals.tf` renders it with `${database}`, `${schema}`, `${table}`,
`${stage}`, and `${file_format}` substitutions.

---

## Dependency Chain

```
S3 bucket (raw-data/json/*.json)
        │
        ▼  s3:ObjectCreated:* → SQS (module.s3_notification)
        ▼  Snowpipe auto-ingest
BRONZE.RAW_NORTHBRIDGE (table)
        │
        ▼  Dynamic Table auto-refresh (target_lag = "downstream")
SILVER.CLEAN_NORTHBRIDGE_DT
        │
        ▼  Dynamic Tables + UDFs
GOLD.* (dims, facts)
```

No streams, no tasks. The SILVER → GOLD chain refreshes through Dynamic
Table dependencies driven by `target_lag = "downstream"`.

---

## Common Mistakes

- **Adding `streams` or `tasks` blocks to the config** — this pipeline
  does not use them. They are not consumed by `locals.tf` and would
  silently be ignored. Use Dynamic Tables instead.
- **Setting `auto_ingest: true` on the very first apply without the
  `enable_snowpipe_creation=false` flag** — the IAM trust policy may
  not yet be reconciled, and the pipe will fail to read from S3 until
  it is. See the deployment sequence in CLAUDE.md.
- **`stage` and `table` referencing JSON map keys instead of Snowflake
  names** — use the Snowflake object `name` values (e.g. `RAW_EXTERNAL_STG`,
  `RAW_NORTHBRIDGE`), not the logical keys (e.g. `raw_external_stg`,
  `raw_northbridge`).
- **`copy_template` set to a path with a leading directory** — pass
  just the filename (e.g. `raw_northbridge_copy.tpl`). `locals.tf`
  prepends `templates/snowpipe-copy-statements/` itself.
- **Omitting `filter_suffix`** — without it, every S3 object created
  under the watched prefix triggers a COPY attempt, including
  non-JSON files.
