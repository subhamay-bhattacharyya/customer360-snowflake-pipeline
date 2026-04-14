---
name: snowflake-config-streams-tasks-pipes
description: >
  Use this skill whenever writing, editing, or validating the `streams`,
  `tasks`, or `snowpipes` blocks inside `infra/platform/tf/config/snowflake/config.json`
  for the Customer 360 / NorthBridge Snowflake pipeline. Trigger when the
  user wants to: add a stream to capture incremental changes from a BRONZE
  table; define a scheduled or stream-triggered task; configure a Snowpipe
  for auto-ingest from S3; wire the Snowpipe COPY statement to a template
  file; set `auto_ingest: true` and understand the SQS notification
  dependency; or debug why the incremental ingestion chain
  (stream → task → pipe) is not firing. Also trigger when the user asks
  about COPY_BANKING_DATA, PROCESS_NORTHBRIDGE_STREAM_TASK, or
  RAW_NORTHBRIDGE_PIPE in the context of this pipeline.
---

# Snowflake Config — Streams, Tasks & Snowpipes

This skill governs the `streams`, `tasks`, and `snowpipes` blocks nested
inside `databases.*.schemas[]` in `infra/platform/tf/config/snowflake/config.json`.
These three object types form the incremental ingestion chain from BRONZE
through SILVER to GOLD.

---

## Streams — JSON Schema

```json
"streams": {
  "<logical_key>": {
    "name":         "<string, required — UPPER_SNAKE_CASE>",
    "database":     "<string, required>",
    "schema":       "<string, required>",
    "source":       "<source_table_name, required>",
    "append_only":  "<bool, default false — true = inserts only, no CDC>",
    "comment":      "<string, optional>"
  }
}
```

### Stream behaviour

| `append_only` | Captures | Use case |
|---|---|---|
| `false` (default) | INSERT, UPDATE, DELETE | Full CDC on mutable tables |
| `true` | INSERT only | Append-only BRONZE tables (recommended for RAW_NORTHBRIDGE) |

> A stream must be consumed (i.e. a DML statement reads `SYSTEM$STREAM_HAS_DATA`)
> before its offset advances. The task that reads the stream is responsible
> for advancing it.

---

## Tasks — JSON Schema

```json
"tasks": {
  "<logical_key>": {
    "name":              "<string, required — UPPER_SNAKE_CASE>",
    "database":          "<string, required>",
    "schema":            "<string, required>",
    "warehouse":         "<WAREHOUSE_NAME, required>",
    "comment":           "<string, optional>",

    "schedule":          "<'n MINUTE' | 'USING CRON expr timezone' — omit if stream-triggered>",
    "stream_trigger":    "<stream_name — omit if schedule-based>",
    "sql_statement":     "<inline SQL — omit if using template file>",
    "sql_template_file": "<relative path to .tpl file — omit if inline SQL>"
  }
}
```

### Schedule vs stream-triggered

| Pattern | When to use | Config field |
|---|---|---|
| Schedule | Periodic batch load (e.g. every 5 minutes) | `schedule: "5 MINUTE"` |
| Stream-triggered | Run only when source stream has data | `stream_trigger: "<stream_name>"` |

> You cannot set both `schedule` and `stream_trigger` on the same task.
> `PROCESS_NORTHBRIDGE_STREAM_TASK` is stream-triggered by `RAW_NORTHBRIDGE_STREAM`.
> `COPY_BANKING_DATA` uses a schedule.

---

## Snowpipes — JSON Schema

```json
"snowpipes": {
  "<logical_key>": {
    "name":              "<string, required — UPPER_SNAKE_CASE>",
    "database":          "<string, required>",
    "schema":            "<string, required>",
    "table":             "<target_table_name, required>",
    "stage":             "<stage_name, required>",
    "file_format":       "<file_format_name, required>",
    "copy_template":     "<relative path to .tpl file, required>",
    "auto_ingest":       "<bool, default false>",
    "comment":           "<string, optional>",

    "filter_prefix":     "<S3 prefix filter, optional>",
    "filter_suffix":     "<file extension filter, optional — e.g. '.json.gz'>"
  }
}
```

### `auto_ingest` and the SQS dependency

When `auto_ingest: true`, Snowflake creates an SQS queue channel on the pipe.
`main.tf` reads `module.pipe.pipes[*].notification_channel` and wires it to
`module.s3_notification`. This happens automatically **only if**
`var.enable_snowpipe_creation = true` at apply time.

Deployment sequence:
1. Pass 1 apply (`enable_trust_policy_update=false`) — creates all objects except Snowpipe
2. Pass 2 apply (`enable_trust_policy_update=true`) — updates IAM trust policy
3. Pass 3 apply (`enable_snowpipe_creation=true`) — creates Snowpipe + wires S3 notification

---

## NorthBridge Pipeline — Standard Patterns

### Stream on BRONZE table

```json
"streams": {
  "raw_northbridge_stream": {
    "name":        "RAW_NORTHBRIDGE_STREAM",
    "database":    "NORTHBRIDGE_DATABASE",
    "schema":      "BRONZE",
    "source":      "RAW_NORTHBRIDGE",
    "append_only": true,
    "comment":     "Captures incremental inserts to trigger downstream task"
  }
}
```

### Scheduled COPY task

```json
"tasks": {
  "copy_banking_data": {
    "name":              "COPY_BANKING_DATA",
    "database":          "NORTHBRIDGE_DATABASE",
    "schema":            "BRONZE",
    "warehouse":         "LOAD_WH",
    "schedule":          "5 MINUTE",
    "sql_template_file": "templates/snowpipe-copy-statements/raw_northbridge_copy.tpl",
    "comment":           "Scheduled COPY INTO from external stage to BRONZE table"
  }
}
```

### Stream-triggered transformation task

```json
"tasks": {
  "process_northbridge_stream_task": {
    "name":           "PROCESS_NORTHBRIDGE_STREAM_TASK",
    "database":       "NORTHBRIDGE_DATABASE",
    "schema":         "BRONZE",
    "warehouse":      "TRANSFORM_WH",
    "stream_trigger": "RAW_NORTHBRIDGE_STREAM",
    "sql_template_file": "templates/dynamic-tables/clean_northbridge.tpl",
    "comment":        "Stream-triggered task — BRONZE → SILVER → GOLD transforms"
  }
}
```

### Snowpipe with auto-ingest

```json
"snowpipes": {
  "raw_northbridge_pipe": {
    "name":          "RAW_NORTHBRIDGE_PIPE",
    "database":      "NORTHBRIDGE_DATABASE",
    "schema":        "BRONZE",
    "table":         "RAW_NORTHBRIDGE",
    "stage":         "RAW_EXTERNAL_STG",
    "file_format":   "JSON_FILE_FORMAT",
    "copy_template": "templates/snowpipe-copy-statements/raw_northbridge_copy.tpl",
    "auto_ingest":   true,
    "filter_suffix": ".json",
    "comment":       "Auto-ingest pipe — S3 → BRONZE.RAW_NORTHBRIDGE"
  }
}
```

---

## Dependency Chain

```
RAW_NORTHBRIDGE (table)
        │
        ▼  append_only stream
RAW_NORTHBRIDGE_STREAM
        │
        ▼  stream_trigger
PROCESS_NORTHBRIDGE_STREAM_TASK  ←→  TRANSFORM_WH
        │
        ▼
SILVER.CLEAN_NORTHBRIDGE_DT (dynamic table)

S3 bucket
        │
        ▼  s3:ObjectCreated:* → SQS → RAW_NORTHBRIDGE_PIPE
BRONZE.RAW_NORTHBRIDGE
```

---

## Common Mistakes

- **Setting both `schedule` and `stream_trigger`** — mutually exclusive; Terraform will fail at validate.
- **`auto_ingest: true` without running the three-pass apply** — the S3 notification cannot be wired until the Snowpipe SQS channel ARN is known (only after pipe creation).
- **`source` referencing a non-existent table** — the stream `source` must match the `name` field of a table in the same schema, not the JSON logical key.
- **`stage` and `table` referencing logical keys instead of Snowflake names** — use the Snowflake object `name` values (e.g. `RAW_EXTERNAL_STG`), not the JSON map keys (e.g. `raw_external_stg`).
- **Running `PROCESS_NORTHBRIDGE_STREAM_TASK` on `LOAD_WH`** — transformation tasks must use `TRANSFORM_WH`, not `LOAD_WH`. Wrong warehouse assignment inflates ingestion costs.