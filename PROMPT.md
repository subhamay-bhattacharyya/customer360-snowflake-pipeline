# Prompt: Update AWS and Snowflake Config JSON Files

## Task

Update both `input-jsons/aws/config.json` and `input-jsons/snowflake/config.json`
to fully configure the NorthBridge Customer 360 pipeline as defined in `CLAUDE.md`
and the project issue.

Before making any changes, read the relevant skill for each block you are about
to edit. Do not generate any config values from memory.

---

## Step 1 — Update `input-jsons/aws/config.json`

### 1a. Read skills first

Read the following skills in order before editing:

1. `aws-config-s3` — for `aws.region`, `aws.s3`, `aws.tf_state`
2. `aws-config-iam-policies` — for `aws.iam.role_name` and `aws.iam.policies[]`
3. `aws-config-trust` — for `trust.snowflake_principal_arn` and `trust.snowflake_external_id`

### 1b. Changes required

**`aws.s3` block:**

- Rename `bucket_name` from `aws-snowflake-project` to `northbridge-raw-data`
- Remove `raw-data/csv` from `bucket_keys` — this pipeline is JSON-only
- Keep `raw-data/json` in `bucket_keys`
- Keep `versioning: true`
- Keep `kms_key_alias: "SB-KMS"`
- Add `force_destroy: false`
- Add a `lifecycle_rules` entry to expire objects under `raw-data/json` after 90 days

**`aws.tf_state` block (add — currently missing):**

- `bucket_name`: `northbridge-tf-state`
- `dynamodb_table`: `northbridge-tf-lock`
- `kms_key_alias`: `SB-KMS`

**`aws.iam` block:**

- Rename `role_name` from `snowflake-external-stage-role` to `northbridge-snowflake-role`
- In `SnowflakeS3ObjectAccessPolicy`: remove `s3:PutObject` and `s3:DeleteObject` — ingestion is read-only
- In `SnowflakeKMSAccessPolicy`: remove `kms:Encrypt` and `kms:ReEncrypt*` — Snowflake only needs to decrypt
- Add a new policy entry for SQS (required for Snowpipe `auto_ingest: true`):
  - `name`: `SnowflakeSQSSendMessagePolicy`
  - `sid`: `SnowflakeSQSSendMessage`
  - `effect`: `Allow`
  - `action`: `sqs:SendMessage`, `sqs:GetQueueUrl`, `sqs:GetQueueAttributes`
  - `resource`: `sqs-queue-arn`

**`trust` block:**

- Leave both `snowflake_principal_arn` and `snowflake_external_id` as `""` — these
  are populated after Pass 1 of `terraform apply` using `DESC INTEGRATION S3_STORAGE_INTEGRATION`

---

## Step 2 — Update `input-jsons/snowflake/config.json`

### 2a. Read skills first

Read the following skills in order before editing each block:

1. `snowflake-config-tables` — before editing any `tables` block
2. `snowflake-config-stages-fileformats` — before editing `stages` or `file_formats`
3. `snowflake-config-streams-tasks-pipes` — before editing `streams`, `tasks`, or `snowpipes`
4. `snowflake-config-dynamic-tables-functions` — before editing `dynamic_tables` or `functions`

### 2b. Changes required

**Warehouses** — add all four warehouses under `warehouses`:

| Key | `name` | `warehouse_size` | `auto_suspend` | `initially_suspended` |
| --- | --- | --- | --- | --- |
| `load_wh` | `LOAD_WH` | `MEDIUM` | `60` | `true` |
| `transform_wh` | `TRANSFORM_WH` | `X-SMALL` | `60` | `true` |
| `streamlit_wh` | `STREAMLIT_WH` | `X-SMALL` | `60` | `true` |
| `adhoc_wh` | `ADHOC_WH` | `X-SMALL` | `60` | `true` |

All warehouses: `auto_resume: true`, `warehouse_type: STANDARD`, `scaling_policy: STANDARD`,
`min_cluster_count: 1`, `max_cluster_count: 1`, `enable_query_acceleration: false`.

**Database** — add `northbridge_database` under `databases`:

- `name`: `NORTHBRIDGE_DATABASE`
- `comment`: `Central analytical database for the NorthBridge Customer 360 pipeline`
- Schemas: `BRONZE`, `SILVER`, `GOLD`, `STREAMLIT` (add all four)

**BRONZE schema — file format:**

- Key: `json_file_format`
- `name`: `JSON_FILE_FORMAT`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `type`: `JSON`
- `compression`: `AUTO`
- `strip_outer_array`: `false`
- `allow_duplicate`: `false`
- `strip_null_values`: `false`
- `ignore_utf8_errors`: `false`
- `enable_octal`: `false`

**BRONZE schema — stages:**

External stage:

- Key: `raw_external_stg`
- `name`: `RAW_EXTERNAL_STG`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `stage_type`: `external`
- `url`: `s3://northbridge-raw-data/raw-data/json/`
- `storage_integration`: `S3_STORAGE_INTEGRATION`
- `file_format`: `JSON_FILE_FORMAT`

Internal stage:

- Key: `raw_internal_stg`
- `name`: `RAW_INTERNAL_STG`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `stage_type`: `internal`
- `file_format`: `JSON_FILE_FORMAT`
- `directory_enabled`: `true`

**BRONZE schema — storage integration** (under `storage_integrations` at root or
within the database block per your config structure):

- `name`: `S3_STORAGE_INTEGRATION`
- `storage_provider`: `S3`
- `storage_allowed_locations`: `["s3://northbridge-raw-data/raw-data/json/"]`
- `enabled`: `true`

**BRONZE schema — table (`RAW_NORTHBRIDGE`):**

- Key: `raw_northbridge`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `name`: `RAW_NORTHBRIDGE`
- `table_type`: `TRANSIENT`
- `drop_before_create`: `true`
- `data_retention_time_in_days`: `1`
- Columns (in order):
  1. `ID` — `NUMBER(38,0)`, `nullable: false`, autoincrement start 1 increment 1, primary key
  2. `INDEX_RECORD_TS` — `TIMESTAMP_NTZ`, `nullable: false`
  3. `JSON_DATA` — `VARIANT`, `nullable: false`
  4. `RECORD_COUNT` — `NUMBER(38,0)`, `nullable: false`
  5. `JSON_VERSION` — `VARCHAR(255)`, `nullable: false`
  6. `_STG_FILE_NAME` — `VARCHAR(500)`, `nullable: true`
  7. `_STG_FILE_LOAD_TS` — `TIMESTAMP_NTZ`, `nullable: true`
  8. `_STG_FILE_MD5` — `VARCHAR(32)`, `nullable: true`
  9. `_COPY_DATA_TS` — `TIMESTAMP_NTZ`, `nullable: true`
- `primary_key.keys`: `["ID"]`

**BRONZE schema — stream:**

- Key: `raw_northbridge_stream`
- `name`: `RAW_NORTHBRIDGE_STREAM`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `source`: `RAW_NORTHBRIDGE`
- `append_only`: `true`

**BRONZE schema — tasks:**

Scheduled COPY task:

- Key: `copy_banking_data`
- `name`: `COPY_BANKING_DATA`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `warehouse`: `LOAD_WH`
- `schedule`: `5 MINUTE`
- `sql_template_file`: `templates/snowpipe-copy-statements/raw_northbridge_copy.tpl`

Stream-triggered transformation task:

- Key: `process_northbridge_stream_task`
- `name`: `PROCESS_NORTHBRIDGE_STREAM_TASK`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `warehouse`: `TRANSFORM_WH`
- `stream_trigger`: `RAW_NORTHBRIDGE_STREAM`
- `sql_template_file`: `templates/dynamic-tables/clean_northbridge.tpl`

Enrichment task:

- Key: `refresh_customer_data_task`

- `name`: `REFRESH_CUSTOMER_DATA_TASK`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `warehouse`: `TRANSFORM_WH`
- `schedule`: `60 MINUTE`

**BRONZE schema — Snowpipe:**

- Key: `raw_northbridge_pipe`
- `name`: `RAW_NORTHBRIDGE_PIPE`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `BRONZE`
- `table`: `RAW_NORTHBRIDGE`
- `stage`: `RAW_EXTERNAL_STG`
- `file_format`: `JSON_FILE_FORMAT`
- `copy_template`: `templates/snowpipe-copy-statements/raw_northbridge_copy.tpl`
- `auto_ingest`: `true`
- `filter_suffix`: `.json`

**SILVER schema — dynamic table:**

- Key: `clean_northbridge_dt`
- `name`: `CLEAN_NORTHBRIDGE_DT`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `SILVER`
- `warehouse`: `LOAD_WH`
- `target_lag`: `downstream`
- `refresh_mode`: `AUTO`
- `initialize`: `ON_CREATE`
- `query_template_file`: `templates/dynamic-tables/clean_northbridge.tpl`
- `grants`: `[{ "role_name": "NORTHBRIDGE_ANALYST", "privileges": ["SELECT"] }]`

**GOLD schema — functions:**

`prominent_index`:

- `name`: `PROMINENT_INDEX`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `GOLD`
- `language`: `JAVASCRIPT`
- `return_type`: `VARCHAR`
- `arguments`: `[{ "name": "credit_score", "type": "NUMBER" }, { "name": "risk_rating", "type": "VARCHAR" }]`
- `body_template_file`: `templates/functions/prominent_index.tpl`
- `grants`: `[{ "role_name": "NORTHBRIDGE_ANALYST", "privileges": ["USAGE"] }]`

`three_sub_index_criteria`:

- `name`: `THREE_SUB_INDEX_CRITERIA`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `GOLD`
- `language`: `SQL`
- `return_type`: `BOOLEAN`
- `arguments`: `[{ "name": "income_tier", "type": "VARCHAR" }, { "name": "credit_tier", "type": "VARCHAR" }, { "name": "kyc_status", "type": "VARCHAR" }]`
- `body_template_file`: `templates/functions/three_sub_index_criteria.tpl`

`get_int`:

- `name`: `GET_INT`
- `database`: `NORTHBRIDGE_DATABASE`
- `schema`: `GOLD`
- `language`: `SQL`
- `return_type`: `NUMBER`
- `arguments`: `[{ "name": "val", "type": "VARIANT" }]`
- `body`: `SELECT val::NUMBER`

---

## Step 3 — Validation checks

After generating both files, verify the following before presenting output:

**AWS config:**

- [ ] `bucket_name` is lowercase with no underscores
- [ ] `raw-data/csv` has been removed from `bucket_keys`
- [ ] `tf_state` block is present with both `bucket_name` and `dynamodb_table`
- [ ] `role_name` is `northbridge-snowflake-role`
- [ ] `s3:PutObject` and `s3:DeleteObject` are absent from all policies
- [ ] `kms:Encrypt` and `kms:ReEncrypt*` are absent from all policies
- [ ] `SnowflakeSQSSendMessagePolicy` is present with resource `sqs-queue-arn`
- [ ] `trust` fields are both `""`

**Snowflake config:**

- [ ] All four warehouses are present; all have `initially_suspended: true`
- [ ] `NORTHBRIDGE_DATABASE` exists with all four schemas
- [ ] `RAW_NORTHBRIDGE` table is `TRANSIENT` with all 9 columns including audit columns
- [ ] `ID` column has `autoincrement` and `primary_key` set; `nullable: false`
- [ ] No VARIANT columns outside of `RAW_NORTHBRIDGE.JSON_DATA`
- [ ] `RAW_NORTHBRIDGE_STREAM` has `append_only: true`
- [ ] `PROCESS_NORTHBRIDGE_STREAM_TASK` uses `stream_trigger`, not `schedule`
- [ ] `COPY_BANKING_DATA` uses `schedule`, not `stream_trigger`
- [ ] `RAW_NORTHBRIDGE_PIPE` has `auto_ingest: true`
- [ ] `CLEAN_NORTHBRIDGE_DT` has `target_lag: downstream` and is in `SILVER` schema
- [ ] All GOLD functions grant `USAGE` (not `SELECT`) to `NORTHBRIDGE_ANALYST`
- [ ] `body` and `body_template_file` are not both set on the same function
