# aws-snowflake-e2e-project

End-to-end data pipeline on Snowflake + AWS. Raw NORTHBRIDGE banking JSON files land on S3, are auto-ingested via Snowpipe into a BRONZE layer, cleansed through a SILVER dynamic table, and modelled in GOLD for Streamlit dashboards. All AWS and Snowflake infrastructure is provisioned via Terraform.

---

## Repository Structure

```text
.
├── infra/platform/tf/               # Terraform root module (main entry point)
│   ├── main.tf                      # Orchestrates all resources
│   ├── variables.tf                 # All input variables
│   ├── locals.tf                    # Computed locals
│   ├── outputs.tf                   # Exported values
│   ├── backend.tf                   # S3 remote state backend
│   ├── providers-aws.tf             # AWS provider config
│   ├── providers-snowflake.tf       # Snowflake provider config (keypair auth)
│   ├── versions.tf                  # Provider + Terraform version constraints
│   ├── terraform.tfvars             # Variable values (gitignored)
│   ├── debug-outputs.tf             # Temporary debug outputs (remove before merge)
│   ├── modules/
│   │   └── iam_role_final/          # IAM role + trust policy for Snowflake S3 access
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── outputs.tf
│   ├── templates/
│   │   ├── bucket-policy/
│   │   │   └── s3-bucket-policy.tpl          # S3 bucket policy template
│   │   ├── dynamic-tables/
│   │   │   └── clean_northbridge.tpl                 # SILVER dynamic table SQL
│   │   └── snowpipe-copy-statements/
│   │       └── raw_northbridge_copy.tpl              # Snowpipe COPY INTO SQL
│   └── tests/
│       ├── config_validation.tftest.hcl      # Input config schema tests
│       └── platform_validation.tftest.hcl    # Post-apply resource tests
├── input-jsons/
│   ├── aws/config.json              # AWS resource definitions (S3, IAM, SQS)
│   └── snowflake/config.json        # Snowflake object definitions (read by Terraform)
└── infra/platform/keypair/
    ├── snowflake_key.p8             # RSA private key — GITIGNORED, never commit
    └── snowflake_key.pub            # RSA public key — register in Snowflake user
```

---

## Terraform Entry Point

All commands run from `infra/platform/tf/`:

```bash
cd infra/platform/tf

terraform init
terraform validate

# Pass 1 — create all resources with placeholder IAM trust policy
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=false"

# Pass 2 — update IAM trust policy with Snowflake storage integration values
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=true"

# Enable Snowpipe creation (after trust policy is confirmed working)
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=true"

# Destroy
terraform destroy -var-file="terraform.tfvars"

# Run tests
terraform test
```

---

## Configuration — Input JSONs

Terraform reads all resource definitions from two JSON files. **Never hardcode resource names in `.tf` files** — everything comes from these configs.

| File | Purpose |
| --- | --- |
| `input-jsons/aws/config.json` | S3 buckets, IAM roles, SQS queues, bucket policies |
| `input-jsons/snowflake/config.json` | Warehouses, database, schemas, stages, file formats, tables, streams, tasks, Snowpipe, dynamic tables, functions |

`input-jsons/snowflake/config.backup.json` is a safe reference copy — do not delete or overwrite it.

---

## Snowflake Authentication

This project uses **RSA keypair authentication** — not username/password.

```bash
# One-time keypair generation
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM \
  -out infra/platform/keypair/snowflake_key.p8 -nocrypt
openssl rsa -in infra/platform/keypair/snowflake_key.p8 \
  -pubout -out infra/platform/keypair/snowflake_key.pub
```

Register the public key in Snowflake (run once as ACCOUNTADMIN):

```sql
ALTER USER <your_user>
  SET RSA_PUBLIC_KEY='<paste contents of snowflake_key.pub — omit header/footer lines>';
```

Reference the key in `terraform.tfvars`:

```hcl
snowflake_private_key_path = "../../keypair/snowflake_key.p8"
```

**`snowflake_key.p8` is gitignored. Never commit it.**

---

## Template Files

SQL logic lives in `.tpl` files under `infra/platform/tf/templates/`. Terraform renders them via `templatefile()`. **Edit the `.tpl`, not inline HCL strings.**

| Template | Rendered into | Purpose |
| --- | --- | --- |
| `bucket-policy/s3-bucket-policy.tpl` | S3 bucket policy | Allows Snowflake storage integration to access S3 |
| `dynamic-tables/clean_northbridge.tpl` | `snowflake_dynamic_table` | SILVER cleansing + typing SQL |
| `snowpipe-copy-statements/raw_northbridge_copy.tpl` | `snowflake_pipe` | `COPY INTO BRONZE.RAW_NORTHBRIDGE` from external stage |

---

## Data Pipeline Flow

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

---

## Warehouses

| Name | Size | Auto-suspend | Purpose |
| --- | --- | --- | --- |
| `LOAD_WH` | MEDIUM | 60s | Snowpipe ingestion + COPY operations |
| `TRANSFORM_WH` | X-SMALL | 60s | Stream tasks, BRONZE → SILVER → GOLD |
| `STREAMLIT_WH` | X-SMALL | 60s | Dashboard queries |
| `ADHOC_WH` | X-SMALL | 60s | Development + ad-hoc debugging |

All warehouses start suspended (`initially_suspended = true`) and auto-resume on demand.

---

## Terraform State

Backend is S3 + DynamoDB, configured in `backend.tf`:

```hcl
terraform {
  backend "s3" {
    bucket         = "<state-bucket-name>"
    key            = "aws-snowflake-e2e/terraform.tfstate"
    region         = "<aws-region>"
    dynamodb_table = "<lock-table-name>"
  }
}
```

**Never commit `terraform.tfstate` or `errored.tfstate` to Git.**

---

## Terraform Orchestration — 5 Phases

`main.tf` provisions resources in a strict dependency order across 5 phases. Never reorder modules or remove `depends_on` chains.

### Phase 1 — AWS resources

- `module.s3` — S3 bucket (landing zone); sourced from `terraform-aws-s3-bucket/modules/bucket`
- `module.iam_role` — IAM role with placeholder trust policy; sourced from `terraform-aws-iam/modules/role`

### Phase 2 — Snowflake resources (each depends on the previous)

- `module.warehouse` — all four warehouses; uses `snowflake.warehouse_provisioner` alias
- `module.database_schemas` — database + schemas; uses `snowflake.db_provisioner` alias
- `module.file_formats` — JSON file format; uses `snowflake.data_object_provisioner` alias
- `module.storage_integrations` — S3 storage integration; uses `snowflake.ingest_object_provisioner` alias
- `module.stage` — external + internal stages
- `module.table` — BRONZE `RAW_NORTHBRIDGE` table (VARIANT + audit columns)

### Phase 3 — AWS trust policy update

- `module.aws_iam_role_final` — local module at `./modules/iam_role_final/`; updates the IAM role trust policy with `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` from the storage integration output
- Controlled by `var.enable_trust_policy_update` (bool) and `local.has_storage_integration_config`

### Phase 4 — Snowpipes (BRONZE layer)

- `module.pipe` — Snowpipe creation; only runs when `var.enable_snowpipe_creation = true`
- `module.s3_notification` — S3 event notifications wired to Snowpipe SQS channels; built dynamically from `module.pipe.pipes` output

### Phase 5 — Dynamic Tables (SILVER layer)

- `module.dynamic_table` — `SILVER.CLEAN_NORTHBRIDGE_DT`; sourced from `terraform-snowflake-dynamic-table`; SQL body from `clean_northbridge.tpl`

---

## Remote Module Sources

All modules except `iam_role_final` are sourced from remote GitHub repositories under the `subhamay-bhattacharyya-tf` org, pinned to `ref=main`. When updating a module version, change the `ref=` parameter — do not copy module code locally.

| Module | Source |
| --- | --- |
| `module.s3` | `github.com/subhamay-bhattacharyya-tf/terraform-aws-s3-bucket/modules/bucket` |
| `module.iam_role` | `github.com/subhamay-bhattacharyya-tf/terraform-aws-iam/modules/role` |
| `module.warehouse` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-warehouse` |
| `module.database_schemas` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-database-schema` |
| `module.file_formats` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-file-format` |
| `module.storage_integrations` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-storage-integration` |
| `module.stage` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-stage` |
| `module.table` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-table` |
| `module.pipe` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-pipe` |
| `module.s3_notification` | `github.com/subhamay-bhattacharyya-tf/terraform-aws-s3-bucket/modules/event-notification` |
| `module.dynamic_table` | `github.com/subhamay-bhattacharyya-tf/terraform-snowflake-dynamic-table` |
| `module.aws_iam_role_final` | `./modules/iam_role_final` (local) |

---

## Provider Aliases

`providers-snowflake.tf` defines multiple Snowflake provider aliases, each scoped to a specific resource type. Always pass the correct alias in each module call — do not use the default provider for Snowflake resources.

| Alias | Used for |
| --- | --- |
| `snowflake.warehouse_provisioner` | Warehouses |
| `snowflake.db_provisioner` | Databases and schemas |
| `snowflake.data_object_provisioner` | Tables, file formats, dynamic tables |
| `snowflake.ingest_object_provisioner` | Storage integrations, stages, pipes |

---

## IAM Trust Policy — Two-Pass Bootstrap

The IAM role trust policy requires two `terraform apply` runs on a fresh deployment because Snowflake's `STORAGE_AWS_IAM_USER_ARN` and `STORAGE_AWS_EXTERNAL_ID` are only known after the storage integration is created.

```text
Pass 1:  terraform apply -var="enable_trust_policy_update=false"
         → Creates S3, IAM role (placeholder trust), all Snowflake objects up to storage integration
         → module.aws_iam_role_final is disabled (enabled = false)

         After pass 1: capture values from Terraform output or run in Snowflake:
         DESC INTEGRATION S3_STORAGE_INTEGRATION;

Pass 2:  terraform apply -var="enable_trust_policy_update=true"
         → module.aws_iam_role_final updates IAM trust policy with real Snowflake values
         → After confirmation, update input-jsons/aws/config.json with these values
         → Future applies need no flag — values are read from config.json
```

---

## Conventions

- **Names come from `input-jsons/`** — never hardcode Snowflake or AWS resource names in `.tf` files
- **SQL goes in `.tpl` templates** — no multi-line SQL strings inside HCL
- **Schema prefix required** in all SQL — write `BRONZE.RAW_NORTHBRIDGE`, never just `RAW_NORTHBRIDGE`
- **`snowflake-ddl/` is reference only** — Terraform is the single source of truth for infra
- **`debug-outputs.tf` must be deleted before merging** to `main`
- **`terraform.tfvars` is gitignored** — copy from `terraform.tfvars.example` to set up locally
- **Keypair files are gitignored** — `.p8` private keys must never be committed
- **`enable_trust_policy_update`** — must be `false` on first apply; `true` only after storage integration exists
- **`enable_snowpipe_creation`** — must be `false` until IAM trust policy is confirmed working
- **Provider aliases are required** — always pass the correct `providers = { snowflake = snowflake.<alias> }` in each module block; never rely on the default Snowflake provider
- **Branch naming**: `feature/SBSNFLK-XXXX-short-description`

---

## Snowflake DDL Folder

`snowflake-ddl/` is reference material, not executed by Terraform. Use it to:

- Understand the full intended schema before editing `input-jsons/snowflake/config.json`
- Manually run account-level one-time setup (resource monitors, network policies, grants)
- Use `scripts/deploy.sh` for manual SQL deployments per environment

```bash
cd snowflake-ddl
./scripts/deploy.sh --env dev
./scripts/rollback.sh --env dev
./scripts/validate.sql   # run in SnowSQL to verify object state
```

---
