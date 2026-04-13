# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

---

## Project Overview

End-to-end data pipeline on Snowflake + AWS. Raw NORTHBRIDGE banking JSON files land on S3, are auto-ingested via Snowpipe into a BRONZE layer, cleansed through a SILVER dynamic table, and modelled in GOLD for Streamlit dashboards. All AWS and Snowflake infrastructure is provisioned via Terraform.

---

## Common Commands

All Terraform commands run from `infra/platform/tf/`:

```bash
cd infra/platform/tf

terraform init
terraform validate
terraform fmt -recursive

# Pass 1 — create resources with placeholder IAM trust policy
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=false"

# Pass 2 — update IAM trust policy with Snowflake storage integration values
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=true"

# Pass 3 — enable Snowpipe (after trust policy is confirmed working)
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=true"

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

CI runs on push to `main`, `feature/**`, `bug/**` branches and on PRs to `main`. It only triggers on changes to `infra/platform/tf/**`, `input-jsons/**`, or `.github/workflows/ci.yaml`. Uses a reusable workflow from `subhamay-bhattacharyya-gha/tf-ci-reusable-wf` with Terraform Cloud remote backend. Changelog is auto-generated via git-cliff on non-main branches; releases are auto-created on merge to main.

---

## Version Constraints

- **Terraform**: >= 1.14.1
- **AWS provider**: >= 5.0
- **Snowflake provider**: >= 1.0.0 (snowflakedb/snowflake)
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
        ▼  RAW_NORTHBRIDGE_STREAM + PROCESS_NORTHBRIDGE_STREAM_TASK
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

1. **AWS resources** — `module.s3` (S3 bucket), `module.iam_role` (IAM role with placeholder trust)
2. **Snowflake resources** (each depends on previous) — `module.warehouse` → `module.database_schemas` → `module.file_formats` → `module.storage_integrations` → `module.stage` → `module.table`
3. **AWS trust policy update** — `module.aws_iam_role_final` (local module at `./modules/iam_role_final/`); updates IAM trust with Snowflake's `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID`. Controlled by `var.enable_trust_policy_update`.
4. **Snowpipes (BRONZE)** — `module.pipe` + `module.s3_notification`; only when `var.enable_snowpipe_creation = true`
5. **Dynamic Tables (SILVER)** — `module.dynamic_table` (`SILVER.CLEAN_NORTHBRIDGE_DT`); SQL from `clean_northbridge.tpl`

### Provider Aliases

`providers-snowflake.tf` defines multiple Snowflake provider aliases. Always pass the correct alias — never use the default Snowflake provider.

| Alias | Used for |
| --- | --- |
| `snowflake.warehouse_provisioner` | Warehouses |
| `snowflake.db_provisioner` | Databases and schemas |
| `snowflake.data_object_provisioner` | Tables, file formats, dynamic tables |
| `snowflake.ingest_object_provisioner` | Storage integrations, stages, pipes |

### Remote Module Sources

All modules except `iam_role_final` are sourced from remote GitHub repos under `subhamay-bhattacharyya-tf` org, pinned to `ref=main`. When updating a module version, change the `ref=` parameter — do not copy module code locally.

---

## Configuration

### Input JSONs

Terraform reads all resource definitions from JSON config files. **Never hardcode resource names in `.tf` files** — everything comes from these configs.

| File | Purpose |
| --- | --- |
| `input-jsons/aws/config.json` | S3 buckets, IAM roles, SQS queues, bucket policies |
| `input-jsons/snowflake/config.json` | Warehouses, database, schemas, stages, file formats, tables, streams, tasks, Snowpipe, dynamic tables, functions |

`input-jsons/snowflake/config.backup.json` is a safe reference copy — do not delete or overwrite it.

Environment-specific overrides live in `input-jsons/aws/{devl,test,prod}/` and `infra/platform/tf/tfvar/{devl,test,prod}/terraform.tfvars`.

### Template Files

SQL logic lives in `.tpl` files under `infra/platform/tf/templates/`. Terraform renders them via `templatefile()`. **Edit the `.tpl`, not inline HCL strings.**

| Template | Purpose |
| --- | --- |
| `bucket-policy/s3-bucket-policy.tpl` | S3 bucket policy for Snowflake storage integration |
| `dynamic-tables/clean_northbridge.tpl` | SILVER cleansing + typing SQL |
| `snowpipe-copy-statements/raw_northbridge_copy.tpl` | `COPY INTO BRONZE.RAW_NORTHBRIDGE` from external stage |

### Snowflake Authentication

Uses **RSA keypair authentication** — not username/password. Key files live in `infra/platform/keypair/` and are gitignored. Reference in `terraform.tfvars`:

```hcl
snowflake_private_key_path = "../../keypair/snowflake_key.p8"
```

---

## IAM Trust Policy — Two-Pass Bootstrap

The IAM role trust policy requires two `terraform apply` runs on a fresh deployment because Snowflake's `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` are only known after the storage integration is created.

- **Pass 1**: `enable_trust_policy_update=false` — creates all resources up to storage integration
- **Pass 2**: `enable_trust_policy_update=true` — updates IAM trust policy with real Snowflake values
- **Pass 3**: `enable_snowpipe_creation=true` — creates Snowpipe after trust is confirmed

---

## Conventions

- **Names come from `input-jsons/`** — never hardcode Snowflake or AWS resource names in `.tf` files
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

| Name | Size | Purpose |
| --- | --- | --- |
| `LOAD_WH` | MEDIUM | Snowpipe ingestion + COPY operations |
| `TRANSFORM_WH` | X-SMALL | Stream tasks, BRONZE → SILVER → GOLD |
| `STREAMLIT_WH` | X-SMALL | Dashboard queries |
| `ADHOC_WH` | X-SMALL | Development + ad-hoc debugging |

All warehouses start suspended (`initially_suspended = true`) and auto-resume on demand. Auto-suspend is 60s.
