# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

End-to-end data pipeline on Snowflake + AWS. Raw NORTHBRIDGE banking JSON files land on S3, are auto-ingested via Snowpipe into a BRONZE layer, cleansed through a SILVER dynamic table, and modelled in GOLD for Streamlit dashboards. All AWS and Snowflake infrastructure is provisioned via Terraform.

---

## Skills

This project uses a set of installed skills. Claude Code **must consult the relevant skill before editing any input JSON config or Terraform template**. Do not generate config blocks from memory — always read the skill first.

### AWS config skills (`infra/platform/tf/config/aws/config.json`)

| Skill                      | Consult when editing                                             |
| -------------------------- | ---------------------------------------------------------------- |
| `aws-config-s3`            | `aws.region`, `aws.s3.*`, `aws.tf_state.*`                       |
| `aws-config-iam-policies`  | `aws.iam.role_name`, `aws.iam.policies[]`                        |

> The previous static `trust` block has been removed. The IAM trust policy is now reconciled at apply time from the live storage integration output — nothing to edit by hand.

### Snowflake config skills (`infra/platform/tf/config/snowflake/config.json`)

| Skill                                        | Consult when editing                                                                                     |
| -------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `snowflake-config-tables`                    | `databases.*.schemas[].tables` — columns, types, primary keys, TRANSIENT vs PERMANENT, audit columns     |
| `snowflake-config-stages-fileformats`        | `schemas[].stages`, `schemas[].file_formats`                                                             |
| `snowflake-config-snowpipes`                 | `schemas[].snowpipes`                                                                                    |
| `snowflake-config-dynamic-tables-functions`  | `schemas[].dynamic_tables`, `schemas[].functions`                                                        |

> Streams and tasks are not used in this pipeline. Ingestion is handled by Snowpipe (auto-ingest from S3) and downstream refreshes are handled by Dynamic Tables (`target_lag = "downstream"`). Do not add `streams` or `tasks` blocks to the config.

### When multiple skills apply

When a task touches more than one config block — for example, adding a new Snowpipe requires editing `snowpipes`, `stages`, and potentially `aws.iam.policies[]` to add SQS permissions — consult **all relevant skills** before making any changes.

---

## Common Commands

All Terraform commands run from `infra/platform/tf/`:

```bash
cd infra/platform/tf

terraform init
terraform validate
terraform fmt -recursive

# Pass A — create core infra; IAM trust is auto-reconciled from the live storage integration output.
# Snowpipe is gated off on the first apply so it doesn't race the trust sync.
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=false"

# Pass B — enable Snowpipe + S3 event notification (default for enable_snowpipe_creation is true)
terraform apply -var-file="terraform.tfvars"

# Destroy
terraform destroy -var-file="terraform.tfvars"

# Run tests
terraform test
```

### Pre-commit Hooks

The repo uses `pre-commit-terraform` hooks. Install and run:

```bash
pre-commit install
pre-commit run --all-files
```

Hooks include: `terraform_fmt`, `terraform_validate`, `terraform_providers_lock`, `terraform_docs`, `terraform_tflint`, `terraform_trivy`, `terrascan`, `checkov` (skips CKV_AWS_8), and `infracost_breakdown` (alerts if costs exceed $0.01/hour or $1/month).

### CI Pipeline

CI runs on push to `main`, `feature/**`, `bug/**` branches and on PRs to `main`. It only triggers on changes to `infra/platform/tf/**`, `infra/platform/tf/config/**`, or `.github/workflows/ci.yaml`. Uses a reusable workflow from `subhamay-bhattacharyya-gha/tf-ci-reusable-wf` with Terraform Cloud remote backend. Changelog is auto-generated via git-cliff on non-main branches; releases are auto-created on merge to main.

---

## Version Constraints

- **Terraform**: >= 1.4.1
- **AWS provider**: >= 5.0
- **Snowflake provider**: >= 1.0.0 (`snowflakedb/snowflake`)
- **Random provider**: >= 3.0
- **Null provider**: >= 3.0

---

## Architecture

### Data Pipeline Flow

```text
S3 raw-data/json/
        │
        ▼  s3:ObjectCreated:* event → SQS (module.s3_notification)
        │
        ▼  Snowpipe auto-ingest (RAW_NORTHBRIDGE_PIPE)
BRONZE.RAW_NORTHBRIDGE          (VARIANT + audit columns)
        │
        ▼  Dynamic Table auto-refresh (target_lag = "downstream")
SILVER.CLEAN_NORTHBRIDGE_DT     (Dynamic Table, typed & cleansed)
        │
        ▼  Dynamic Tables + UDFs
GOLD.*                          (Dims, Facts, Views)
        │
        ▼  Streamlit in Snowflake
STREAMLIT schema                (Dashboard scripts)
```

### Terraform Orchestration — 5 Phases

`main.tf` provisions resources in a strict dependency order across 5 phases. **Never reorder modules or remove `depends_on` chains.**

1. **AWS resources** — `module.s3` (S3 bucket), `module.iam_role` (IAM role; trust policy computed from the live storage integration output via `local.assume_role_policy`, or account-root placeholder on first create)
2. **Snowflake resources** (each depends on previous) — `module.warehouse` → `module.database_schemas` → `module.file_formats` → `module.storage_integrations` → `module.stage` → `module.table`
3. **AWS trust policy reconcile** — `module.aws_iam_role_final` (local module at `./modules/iam_role_final/`); on every apply, re-pushes the current `STORAGE_AWS_IAM_USER_ARN` / `STORAGE_AWS_EXTERNAL_ID` to the IAM role via AWS CLI. No manual flag — fires whenever a storage integration is configured.
4. **Snowpipes (BRONZE)** — `module.pipe` + `module.s3_notification`; only when `var.enable_snowpipe_creation = true` (default `true`; set `false` only on the very first apply to avoid racing the trust sync)
5. **Dynamic Tables (SILVER)** — `module.dynamic_table` (`SILVER.CLEAN_NORTHBRIDGE_DT`); SQL from `clean_northbridge.tpl`

### Provider Aliases

`providers-snowflake.tf` defines multiple Snowflake provider aliases. Always pass the correct alias — never use the default Snowflake provider.

| Alias                                  | Used for                              |
| -------------------------------------- | ------------------------------------- |
| `snowflake.warehouse_provisioner`      | Warehouses                            |
| `snowflake.db_provisioner`             | Databases and schemas                 |
| `snowflake.data_object_provisioner`    | Tables, file formats, dynamic tables  |
| `snowflake.ingest_object_provisioner`  | Storage integrations, stages, pipes   |

### Remote Module Sources

All modules except `iam_role_final` are sourced from remote GitHub repos under `subhamay-bhattacharyya-tf` org, pinned to `ref=main`. When updating a module version, change the `ref=` parameter — do not copy module code locally.

---

## Configuration

### Input JSONs

Terraform reads all resource definitions from JSON config files. **Never hardcode resource names in `.tf` files** — everything comes from these configs.

> **Always consult the relevant skill before editing a config file.** See the [Skills](#skills) section above for the skill-to-block mapping.

| File                                | Purpose                                                                                                          | Skills                                                                                                                                                |
| ----------------------------------- | ---------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `infra/platform/tf/config/aws/config.json`       | S3, IAM role, IAM policies                                                                                       | `aws-config-s3`, `aws-config-iam-policies`                                                                                                            |
| `infra/platform/tf/config/snowflake/config.json` | Warehouses, database, schemas, stages, file formats, tables, Snowpipe, dynamic tables, functions | `snowflake-config-tables`, `snowflake-config-stages-fileformats`, `snowflake-config-snowpipes`, `snowflake-config-dynamic-tables-functions` |

`infra/platform/tf/config/snowflake/config.backup.json` is a safe reference copy — do not delete or overwrite it.

Environment-specific overrides live in `infra/platform/tf/config/aws/{devl,test,prod}/` and `infra/platform/tf/environments/{devl,test,prod}/terraform.tfvars`.

### AWS Config JSON structure

> Consult `aws-config-s3` and `aws-config-iam-policies` skills before editing.

```text
infra/platform/tf/config/aws/config.json
├── aws.region                    ← aws-config-s3
├── aws.s3.*                      ← aws-config-s3
│   ├── bucket_name, bucket_keys, versioning, kms_key_alias
│   └── lifecycle_rules[]
└── aws.iam.*                     ← aws-config-iam-policies
    ├── role_name
    └── policies[]
        └── name, sid, effect, action[], resource
```

> The `trust` block is gone. `module.aws_iam_role_final` reads Snowflake's `STORAGE_AWS_IAM_USER_ARN` / `STORAGE_AWS_EXTERNAL_ID` from the storage integration module output at apply time — no manual DESC / edit needed.

### Snowflake Config JSON structure

> Consult the appropriate Snowflake skill before editing each block.

```text
infra/platform/tf/config/snowflake/config.json
├── warehouses.*                  ← no dedicated skill; follow existing patterns
├── databases.*.schemas[]
│   ├── tables.*                  ← snowflake-config-tables
│   ├── stages.*                  ← snowflake-config-stages-fileformats
│   ├── file_formats.*            ← snowflake-config-stages-fileformats
│   ├── snowpipes.*               ← snowflake-config-snowpipes
│   ├── dynamic_tables.*          ← snowflake-config-dynamic-tables-functions
│   └── functions.*               ← snowflake-config-dynamic-tables-functions
```

### Template Files

SQL logic lives in `.tpl` files under `infra/platform/tf/templates/`. Terraform renders them via `templatefile()`. **Edit the `.tpl`, not inline HCL strings.**

| Template                                               | Purpose                                                | Related skill                                  |
| ------------------------------------------------------ | ------------------------------------------------------ | ---------------------------------------------- |
| `bucket-policy/s3-bucket-policy.tpl`                   | S3 bucket policy for Snowflake storage integration     | `aws-config-iam-policies`                      |
| `dynamic-tables/clean_northbridge.tpl`                 | SILVER cleansing + typing SQL                          | `snowflake-config-dynamic-tables-functions`    |
| `snowpipe-copy-statements/raw_northbridge_copy.tpl`    | `COPY INTO BRONZE.RAW_NORTHBRIDGE` from external stage | `snowflake-config-snowpipes`                   |

### Snowflake Authentication

Uses **RSA keypair authentication** — not username/password. Key files live in `infra/platform/keypair/` and are gitignored. Reference in `terraform.tfvars`:

```hcl
snowflake_private_key_path = "../../keypair/snowflake_key.p8"
```

---

## IAM Trust Policy — Apply-Time Reconcile

The IAM role's trust policy is computed from the live storage integration output (`STORAGE_AWS_IAM_USER_ARN`, `STORAGE_AWS_EXTERNAL_ID`) at apply time — no static JSON config, no `DESC INTEGRATION` / manual edit step.

Flow:
- **First apply**: storage integration doesn't exist yet, so `local.assume_role_policy` falls back to an account-root placeholder on the IAM role. Immediately after, `module.storage_integrations` creates the integration; `module.aws_iam_role_final` (local module) runs `aws iam update-assume-role-policy` via `local-exec` to push the real Snowflake trust. All in the same apply.
- **Subsequent applies**: `local.snowflake_iam_user_arn_runtime` / `local.snowflake_external_id_runtime` are populated from the refreshed integration output, so `local.assume_role_policy` already matches reality — no drift on `module.iam_role`. `module.aws_iam_role_final`'s `always_run` trigger still re-runs the CLI reconcile as a safety net (idempotent).
- **On `terraform destroy`**: nothing special — both modules destroy cleanly.

One edge on **fresh bootstrap only**: set `-var="enable_snowpipe_creation=false"` on the very first apply so Snowpipe doesn't race the trust sync. Default for that variable is `true`, so subsequent applies need no flags.

---

## Conventions

- **Names come from `infra/platform/tf/config/`** — never hardcode Snowflake or AWS resource names in `.tf` files
- **Consult the relevant skill before editing config JSON** — see [Skills](#skills) for the mapping
- **SQL goes in `.tpl` templates** — no multi-line SQL strings inside HCL
- **Schema prefix required** in all SQL — write `BRONZE.RAW_NORTHBRIDGE`, never just `RAW_NORTHBRIDGE`
- **`snowflake-ddl/` is reference only** — Terraform is the single source of truth for infra
- **`debug-outputs.tf` must be deleted before merging** to `main`
- **`terraform.tfvars` is gitignored** — copy from `terraform.tfvars.example` to set up locally
- **Keypair files are gitignored** — `.p8` private keys must never be committed
- **Provider aliases are required** — always pass the correct `providers = { snowflake = snowflake.<alias> }` in each module block
- **Branch naming**: `feature/SBSNFLK-XXXX-short-description`

---

## Warehouses

| Name           | Size    | Purpose                                       |
| -------------- | ------- | --------------------------------------------- |
| `LOAD_WH`      | MEDIUM  | Snowpipe ingestion + COPY operations          |
| `TRANSFORM_WH` | X-SMALL | Dynamic Table refresh, BRONZE → SILVER → GOLD |
| `STREAMLIT_WH` | X-SMALL | Dashboard queries                             |
| `ADHOC_WH`     | X-SMALL | Development + ad-hoc debugging                |

All warehouses start suspended (`initially_suspended = true`) and auto-resume on demand. Auto-suspend is 60s.
