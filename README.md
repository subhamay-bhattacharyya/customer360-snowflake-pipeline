# Customer 360 Analytics Pipeline — Snowflake Data Lake on AWS

![Built with Claude Code](https://img.shields.io/badge/Built_with-Claude_Code-D97757?logo=anthropic&logoColor=white)&nbsp;![Built with Snowflake CoCo](https://img.shields.io/badge/Built_with-Snowflake_CoCo-29B5E8?logo=snowflake&logoColor=white)&nbsp;![Commit Activity](https://img.shields.io/github/commit-activity/t/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Last Commit](https://img.shields.io/github/last-commit/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Release Date](https://img.shields.io/github/release-date/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Repo Size](https://img.shields.io/github/repo-size/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![File Count](https://img.shields.io/github/directory-file-count/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Issues](https://img.shields.io/github/issues/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Top Language](https://img.shields.io/github/languages/top/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Custom Endpoint](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bsubhamay/a67e3709024d310f0c41772c4b1c628d/raw/customer360-snowflake-pipeline.json?)

A Terraform-managed Snowflake data lake that ingests 25,000 nested JSON banking records through a BRONZE → SILVER → GOLD medallion pipeline and surfaces a Customer 360 risk analytics dashboard via Streamlit in Snowflake.

---

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
  - [1. Generate RSA Keypair](#1-generate-rsa-keypair)
  - [2. Create Snowflake Service User and Roles](#2-create-snowflake-service-user-and-roles)
  - [3. Configure HCP Terraform Variable Sets](#3-configure-hcp-terraform-variable-sets)
  - [4. Configure Local Terraform Variables](#4-configure-local-terraform-variables)
  - [5. Deploy Infrastructure](#5-deploy-infrastructure)
  - [6. Upload Source Data](#6-upload-source-data)
  - [7. Verify the Pipeline](#7-verify-the-pipeline)
  - [8. Deploy the Streamlit Dashboard](#8-deploy-the-streamlit-dashboard)
- [Snowflake Objects](#snowflake-objects)
- [Streamlit Dashboard](#streamlit-dashboard)
- [Dataset](#dataset)
- [Domain Glossary](#domain-glossary)
- [Teardown](#teardown)
- [License](#license)

---

## Overview

**NorthBridge Bank** is a fictional retail bank whose customer data is fragmented across core banking, loan origination, CRM, and transaction processing systems. This project consolidates that data into a unified analytical layer on Snowflake, enabling:

- Customer 360 profiling across all products and channels
- Loan portfolio health monitoring and NPL tracking
- Transaction trend analysis by channel, segment, and region
- AML/KYC compliance risk scoring and flagging

All AWS and Snowflake infrastructure is provisioned via **Terraform** with a config-driven approach — resource names come from `input-jsons/` and are never hardcoded in `.tf` files.

---

## Architecture

### Data Pipeline

```text
S3 (northbridge-raw-data/raw-data/json/)
        │
        ▼  s3:ObjectCreated:* → SQS event notification
        │
        ▼  Snowpipe auto-ingest (RAW_NORTHBRIDGE_PIPE)
BRONZE  →  RAW_NORTHBRIDGE          (VARIANT + audit columns, 25,000 records)
        │
        ▼  RAW_NORTHBRIDGE_STREAM → PROCESS_NORTHBRIDGE_STREAM_TASK
SILVER  →  CLEAN_NORTHBRIDGE_DT    (Dynamic Table — typed & cleansed)
        │
        ▼  Dynamic Tables + UDFs (PROMINENT_INDEX, THREE_SUB_INDEX_CRITERIA, GET_INT)
GOLD    →  DIM_CUSTOMER · DIM_BRANCH · DIM_PRODUCT · DIM_DATE
           FACT_TRANSACTIONS · FACT_LOANS · FACT_ACCOUNT_BALANCES
           V_KPI_SUMMARY · V_SEGMENT_STATS · V_LOAN_PORTFOLIO
           V_MONTHLY_TXN_TRENDS · V_REGIONAL_PERF · V_RISK_DISTRIBUTION
        │
        ▼  Streamlit in Snowflake (STREAMLIT_WH)
STREAMLIT → Customer 360 Dashboard  (5 tabs · sidebar filters)
```

### Terraform Provisioning — 5 Phases

```text
Phase 1 ── AWS Resources
           module.s3          → S3 bucket (landing zone + Terraform state)
           module.iam_role    → IAM role (placeholder trust policy)

Phase 2 ── Snowflake Resources (strict dependency order)
           module.warehouse           → LOAD_WH · TRANSFORM_WH · STREAMLIT_WH · ADHOC_WH
           module.database_schemas    → NORTHBRIDGE_DATABASE + 4 schemas
           module.file_formats        → JSON_FILE_FORMAT
           module.storage_integrations → S3_STORAGE_INTEGRATION
           module.stage               → RAW_EXTERNAL_STG · RAW_INTERNAL_STG
           module.table               → BRONZE.RAW_NORTHBRIDGE

Phase 3 ── AWS Trust Policy Update
           module.aws_iam_role_final  → Updates IAM trust with Snowflake ARN + external ID
                                        (enable_trust_policy_update=true)

Phase 4 ── Snowpipes — BRONZE layer
           module.pipe                → RAW_NORTHBRIDGE_PIPE (auto_ingest=true)
           module.s3_notification     → S3 event → SQS wiring
                                        (enable_snowpipe_creation=true)

Phase 5 ── Dynamic Tables — SILVER layer
           module.dynamic_table       → SILVER.CLEAN_NORTHBRIDGE_DT
```

---

## Repository Structure

```text
customer360-snowflake-pipeline/
├── CLAUDE.md                              # Claude Code project context
├── README.md
├── PROMPT.md                              # Claude Code prompt for config generation
├── CHANGELOG.md
│
├── infra/platform/
│   ├── keypair/                           # RSA keys — GITIGNORED
│   │   ├── snowflake_key.p8               # Private key — never commit
│   │   └── snowflake_key.pub              # Public key
│   └── tf/                               # Terraform root module
│       ├── main.tf                        # 5-phase orchestration
│       ├── variables.tf
│       ├── locals.tf
│       ├── outputs.tf
│       ├── backend.tf                     # S3 + DynamoDB remote state
│       ├── providers-aws.tf
│       ├── providers-snowflake.tf         # Multiple provider aliases
│       ├── versions.tf
│       ├── debug-outputs.tf               # Remove before merging to main
│       ├── modules/
│       │   └── iam_role_final/            # Local IAM trust policy update module
│       ├── templates/
│       │   ├── bucket-policy/
│       │   │   └── s3-bucket-policy.tpl
│       │   ├── dynamic-tables/
│       │   │   └── clean_northbridge.tpl
│       │   └── snowpipe-copy-statements/
│       │       └── raw_northbridge_copy.tpl
│       └── tests/
│           ├── config_validation.tftest.hcl
│           └── platform_validation.tftest.hcl
│
├── input-jsons/
│   ├── aws/
│   │   └── config.json                   # S3, IAM, trust block
│   └── snowflake/
│       ├── config.json                   # All Snowflake objects
│       └── config.backup.json            # Reference copy — do not overwrite
│
├── snowflake-ddl/                        # Reference DDL only — not run by Terraform
│   ├── 00_account/
│   ├── 01_security/
│   ├── 02_warehouses/
│   ├── 03_databases/
│   ├── 04_storage/
│   ├── 05_schemas/
│   ├── 06_pipes/
│   ├── 07_tasks/
│   ├── 08_functions/
│   ├── 09_procedures/
│   └── scripts/
│
├── app/
│   └── northbridge_dashboard.py          # Streamlit in Snowflake dashboard
│
└── scripts/
    └── gen_large.py                      # Synthetic dataset generator (seed=2025)
```

---

## Prerequisites

| Tool | Version | Purpose |
| --- | --- | --- |
| Terraform | `>= 1.14.1` | Infrastructure provisioning |
| Snowflake provider | `snowflakedb/snowflake >= 1.0.0` | Snowflake resources |
| AWS provider | `hashicorp/aws >= 5.0` | AWS resources |
| OpenSSL | Any current version | RSA keypair generation |
| HCP Terraform | Account required | Remote state + CI variable sets |
| Python | `>= 3.10` | Dataset generation only |

---

## Getting Started

### 1. Generate RSA Keypair

Snowflake uses RSA keypair authentication (JWT) instead of username/password. Generate the keys and store them in `infra/platform/keypair/` (gitignored):

```bash
mkdir -p infra/platform/keypair && cd infra/platform/keypair

# Step 1 — Generate 2048-bit RSA private key in PKCS#8 (unencrypted) format
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt

# Step 2 — Derive the public key
openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub

# Step 3 — Extract the public key body (strip headers and newlines) for Snowflake
grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC" | tr -d '\n'
```

Copy the output of Step 3 — you will need it in the next step.

---

### 2. Create Snowflake Service User and Roles

#### 2a. Create provisioner roles and the GitHub Actions service user

Each Terraform module uses a dedicated, least-privilege role so that no single role has broader permissions than its scope of work. The role names below are the defaults from `infra/platform/tf/variables.tf` and can be overridden per environment via `terraform.tfvars`.

| Role | Scope | Used by Terraform module |
| --- | --- | --- |
| `DB_PROVISIONER` | Create databases and schemas | `module.database_schemas` |
| `WAREHOUSE_PROVISIONER` | Create and manage warehouses | `module.warehouse` |
| `DATA_OBJECT_PROVISIONER` | Create tables, file formats, and dynamic tables | `module.table`, `module.file_formats`, `module.dynamic_table` |
| `INGEST_OBJECT_PROVISIONER` | Create storage integrations, stages, and pipes | `module.storage_integrations`, `module.stage`, `module.pipe` |

Run the SQL below as `SECURITYADMIN` / `ACCOUNTADMIN`. Replace `YOUR_PUBLIC_KEY_HERE` with the output from Step 1.3.

```sql
-- ============================================================================
-- GitHub Actions Service User + Least-Privilege Provisioner Roles
-- ============================================================================

USE ROLE SECURITYADMIN;

-- ----------------------------------------------------------------------------
-- 1) Create provisioner roles
-- ----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS DB_PROVISIONER
  COMMENT = 'Terraform: creates databases and schemas';

CREATE ROLE IF NOT EXISTS WAREHOUSE_PROVISIONER
  COMMENT = 'Terraform: creates and manages warehouses';

CREATE ROLE IF NOT EXISTS DATA_OBJECT_PROVISIONER
  COMMENT = 'Terraform: creates tables, file formats, and dynamic tables';

CREATE ROLE IF NOT EXISTS INGEST_OBJECT_PROVISIONER
  COMMENT = 'Terraform: creates storage integrations, stages, and pipes';

-- Role hierarchy — all provisioners report to SYSADMIN for governance
GRANT ROLE DB_PROVISIONER            TO ROLE SYSADMIN;
GRANT ROLE WAREHOUSE_PROVISIONER     TO ROLE SYSADMIN;
GRANT ROLE DATA_OBJECT_PROVISIONER   TO ROLE SYSADMIN;
GRANT ROLE INGEST_OBJECT_PROVISIONER TO ROLE SYSADMIN;

-- ----------------------------------------------------------------------------
-- 2) Grant account-level privileges (least privilege — only what each role needs)
-- ----------------------------------------------------------------------------
USE ROLE ACCOUNTADMIN;

-- DB_PROVISIONER — only allowed to create databases
GRANT CREATE DATABASE ON ACCOUNT TO ROLE DB_PROVISIONER;

-- WAREHOUSE_PROVISIONER — only allowed to create/manage warehouses
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE WAREHOUSE_PROVISIONER;
GRANT MONITOR USAGE    ON ACCOUNT TO ROLE WAREHOUSE_PROVISIONER;

-- INGEST_OBJECT_PROVISIONER — only allowed to create storage integrations
-- (stages/pipes are schema-level, granted post-database in Step 2c)
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE INGEST_OBJECT_PROVISIONER;

-- DATA_OBJECT_PROVISIONER — intentionally receives NO account-level privileges.
-- All its privileges are schema-scoped and granted in Step 2c after the
-- database/schemas are created by DB_PROVISIONER via Terraform.

-- All roles need a warehouse to run queries — the tiny UTIL_WH is fine here
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE DB_PROVISIONER;
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE WAREHOUSE_PROVISIONER;
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE DATA_OBJECT_PROVISIONER;
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE INGEST_OBJECT_PROVISIONER;

-- ----------------------------------------------------------------------------
-- 3) Create the GitHub Actions service user (keypair auth only, no password)
-- ----------------------------------------------------------------------------
USE ROLE SECURITYADMIN;

CREATE USER IF NOT EXISTS GITHUB_ACTIONS_USER
  LOGIN_NAME           = 'GITHUB_ACTIONS_USER'
  DISPLAY_NAME         = 'GitHub Actions Service User'
  DEFAULT_ROLE         = PUBLIC
  DEFAULT_WAREHOUSE    = NULL
  MUST_CHANGE_PASSWORD = FALSE
  DISABLED             = FALSE
  COMMENT              = 'Service account for Terraform deployments via GitHub Actions'
  RSA_PUBLIC_KEY       = 'YOUR_PUBLIC_KEY_HERE';

-- ----------------------------------------------------------------------------
-- 4) Grant provisioner roles to the service user
-- ----------------------------------------------------------------------------
GRANT ROLE DB_PROVISIONER            TO USER GITHUB_ACTIONS_USER;
GRANT ROLE WAREHOUSE_PROVISIONER     TO USER GITHUB_ACTIONS_USER;
GRANT ROLE DATA_OBJECT_PROVISIONER   TO USER GITHUB_ACTIONS_USER;
GRANT ROLE INGEST_OBJECT_PROVISIONER TO USER GITHUB_ACTIONS_USER;

-- ----------------------------------------------------------------------------
-- 5) Verify
-- ----------------------------------------------------------------------------
SHOW USERS LIKE 'GITHUB_ACTIONS_USER';
SHOW GRANTS TO USER GITHUB_ACTIONS_USER;
SHOW GRANTS TO ROLE DB_PROVISIONER;
SHOW GRANTS TO ROLE WAREHOUSE_PROVISIONER;
SHOW GRANTS TO ROLE DATA_OBJECT_PROVISIONER;
SHOW GRANTS TO ROLE INGEST_OBJECT_PROVISIONER;
```

#### 2b. Create the analyst read-only role

Run as `ACCOUNTADMIN`. Replace `<DATABASE_NAME>`, `<SCHEMA_NAME>`, and `<ANALYST_USERNAME>` as required.

```sql
-- ============================================================================
-- Analyst Role — Read-Only Access
-- ============================================================================

CREATE ROLE IF NOT EXISTS NORTHBRIDGE_ANALYST
  COMMENT = 'Read-only access to GOLD schema tables, views, and UDFs';

GRANT ROLE NORTHBRIDGE_ANALYST TO ROLE SYSADMIN;

-- Warehouse access
GRANT USAGE ON WAREHOUSE STREAMLIT_WH TO ROLE NORTHBRIDGE_ANALYST;

-- Database and schema access
GRANT USAGE ON DATABASE NORTHBRIDGE_DATABASE                TO ROLE NORTHBRIDGE_ANALYST;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.GOLD           TO ROLE NORTHBRIDGE_ANALYST;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.STREAMLIT      TO ROLE NORTHBRIDGE_ANALYST;

-- Current and future object grants
GRANT SELECT ON ALL TABLES  IN SCHEMA NORTHBRIDGE_DATABASE.GOLD      TO ROLE NORTHBRIDGE_ANALYST;
GRANT SELECT ON ALL VIEWS   IN SCHEMA NORTHBRIDGE_DATABASE.GOLD      TO ROLE NORTHBRIDGE_ANALYST;
GRANT USAGE  ON ALL FUNCTIONS IN SCHEMA NORTHBRIDGE_DATABASE.GOLD    TO ROLE NORTHBRIDGE_ANALYST;

GRANT SELECT ON FUTURE TABLES   IN SCHEMA NORTHBRIDGE_DATABASE.GOLD  TO ROLE NORTHBRIDGE_ANALYST;
GRANT SELECT ON FUTURE VIEWS    IN SCHEMA NORTHBRIDGE_DATABASE.GOLD  TO ROLE NORTHBRIDGE_ANALYST;
GRANT USAGE  ON FUTURE FUNCTIONS IN SCHEMA NORTHBRIDGE_DATABASE.GOLD TO ROLE NORTHBRIDGE_ANALYST;

-- Grant to analyst users
GRANT ROLE NORTHBRIDGE_ANALYST TO USER <ANALYST_USERNAME>;
```

#### 2c. Post-database grants (run after `terraform apply` Phase 2)

After Terraform Phase 2 creates the database and schemas, run these grants as `ACCOUNTADMIN` to give the provisioner roles the schema-scoped privileges they need to build downstream objects:

```sql
USE ROLE ACCOUNTADMIN;

-- ----------------------------------------------------------------------------
-- DATA_OBJECT_PROVISIONER — table / file format / dynamic table creation
-- ----------------------------------------------------------------------------
GRANT USAGE ON DATABASE NORTHBRIDGE_DATABASE                           TO ROLE DATA_OBJECT_PROVISIONER;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.BRONZE                    TO ROLE DATA_OBJECT_PROVISIONER;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.SILVER                    TO ROLE DATA_OBJECT_PROVISIONER;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.GOLD                      TO ROLE DATA_OBJECT_PROVISIONER;

GRANT CREATE FILE FORMAT   ON SCHEMA NORTHBRIDGE_DATABASE.BRONZE       TO ROLE DATA_OBJECT_PROVISIONER;
GRANT CREATE TABLE         ON SCHEMA NORTHBRIDGE_DATABASE.BRONZE       TO ROLE DATA_OBJECT_PROVISIONER;
GRANT CREATE DYNAMIC TABLE ON SCHEMA NORTHBRIDGE_DATABASE.SILVER       TO ROLE DATA_OBJECT_PROVISIONER;
GRANT CREATE TABLE         ON SCHEMA NORTHBRIDGE_DATABASE.GOLD         TO ROLE DATA_OBJECT_PROVISIONER;
GRANT CREATE VIEW          ON SCHEMA NORTHBRIDGE_DATABASE.GOLD         TO ROLE DATA_OBJECT_PROVISIONER;
GRANT CREATE FUNCTION      ON SCHEMA NORTHBRIDGE_DATABASE.GOLD         TO ROLE DATA_OBJECT_PROVISIONER;

-- ----------------------------------------------------------------------------
-- INGEST_OBJECT_PROVISIONER — stage / pipe creation (integrations already granted in 2a)
-- ----------------------------------------------------------------------------
GRANT USAGE ON DATABASE NORTHBRIDGE_DATABASE                           TO ROLE INGEST_OBJECT_PROVISIONER;
GRANT USAGE ON SCHEMA   NORTHBRIDGE_DATABASE.BRONZE                    TO ROLE INGEST_OBJECT_PROVISIONER;

GRANT CREATE STAGE ON SCHEMA NORTHBRIDGE_DATABASE.BRONZE               TO ROLE INGEST_OBJECT_PROVISIONER;
GRANT CREATE PIPE  ON SCHEMA NORTHBRIDGE_DATABASE.BRONZE               TO ROLE INGEST_OBJECT_PROVISIONER;

-- INGEST_OBJECT_PROVISIONER also needs SELECT on the target table so COPY INTO works via Snowpipe
GRANT USAGE  ON FUTURE TABLES IN SCHEMA NORTHBRIDGE_DATABASE.BRONZE    TO ROLE INGEST_OBJECT_PROVISIONER;
GRANT INSERT ON FUTURE TABLES IN SCHEMA NORTHBRIDGE_DATABASE.BRONZE    TO ROLE INGEST_OBJECT_PROVISIONER;
```

To verify the keypair was assigned correctly:

```sql
DESC USER GITHUB_ACTIONS_USER;
-- Look for RSA_PUBLIC_KEY_FP — should show SHA256:...
```

To rotate the key later:

```sql
ALTER USER GITHUB_ACTIONS_USER SET RSA_PUBLIC_KEY = '<new public key body>';
```

---

### 3. Configure HCP Terraform Variable Sets

Variables are split between HCP Variable Sets (secrets and account-level values shared across all environments) and per-environment `.tfvars` files (non-sensitive values that vary per environment).

#### 3a. Snowflake credentials variable set

In HCP Terraform: **Organization Settings → Variable sets → Create variable set**

- Name: `SNOWFLAKE_CREDENTIALS`
- Scope: Apply to all projects and workspaces

| Variable | Category | HCL | Sensitive | How to obtain |
| --- | --- | --- | --- | --- |
| `snowflake_private_key` | Terraform | No | ✅ Yes | `base64 -i infra/platform/keypair/snowflake_key.p8 \| tr -d '\n'` |
| `TF_VAR_snowflake_organization_name` | Environment | N/A | No | `SELECT CURRENT_ORGANIZATION_NAME();` in Snowflake |
| `TF_VAR_snowflake_account_name` | Environment | N/A | No | `SELECT CURRENT_ACCOUNT_NAME();` in Snowflake |
| `TF_VAR_snowflake_user` | Environment | N/A | No | `GITHUB_ACTIONS_USER` |

> **Important:**
>
> - For `snowflake_private_key` — set Category = **Terraform**, HCL = **unchecked**, Sensitive = **checked**. The value is the base64-encoded entire `.p8` file including PEM headers. The Terraform provider decodes it with `base64decode()` at runtime.
> - For the three `TF_VAR_*` variables — set Category = **Environment**. HCP injects them as OS env vars and Terraform picks them up automatically.
> - Do **not** create `SNOWFLAKE_PRIVATE_KEY` as an environment variable — HCP strips newlines from env vars, breaking the PEM format.
> - When copying the base64 value, do **not** include any trailing `%` shown by your shell.

#### 3b. AWS credentials variable set

Create a second variable set named `AWS_VARIABLE_SET` (applied to all projects and workspaces):

| Variable | Category | Sensitive | Value |
| --- | --- | --- | --- |
| `AWS_ACCESS_KEY_ID` | Environment | No | Access key of the deployer IAM user |
| `AWS_SECRET_ACCESS_KEY` | Environment | ✅ Yes | Secret key of the deployer IAM user |

#### 3c. Per-environment `.tfvars` files

These live in `infra/platform/tf/environments/{devl,test,prod}/terraform.tfvars` and are committed to version control. They vary per environment:

| Variable | Description | Example (devl) |
| --- | --- | --- |
| `db_provisioner_role` | Role for database/schema ops | `PLATFORM_DB_OWNER` |
| `warehouse_provisioner_role` | Role for warehouse ops | `WAREHOUSE_ADMIN` |
| `data_object_provisioner_role` | Role for table/file format ops | `DATA_OBJECT_ADMIN` |
| `ingest_object_provisioner_role` | Role for stage/pipe ops | `INGEST_ADMIN` |
| `snowflake_warehouse` | Default warehouse for Terraform ops | `UTIL_WH` |
| `aws_config_path` | Path to AWS config JSON | `input-jsons/aws/devl/config.json` |
| `snowflake_config_path` | Path to Snowflake config JSON | `input-jsons/snowflake/devl/config.json` |
| `project_code` | Short prefix for resource naming | `cust360sf` |

---

### 4. Configure Local Terraform Variables

For local development, copy the environment tfvars and export Snowflake connection variables:

```bash
cd infra/platform/tf
cp environments/devl/terraform.tfvars terraform.tfvars

# Export Snowflake connection variables (these come from the HCP Variable Set in CI)
export SNOWFLAKE_PRIVATE_KEY="$(cat ../../keypair/snowflake_key.p8)"
export TF_VAR_snowflake_organization_name="YOUR_ORG"
export TF_VAR_snowflake_account_name="YOUR_ACCOUNT"
export TF_VAR_snowflake_user="GITHUB_ACTIONS_USER"
```

---

### 5. Deploy Infrastructure

Infrastructure is deployed in three passes due to the IAM trust policy bootstrap requirement.

```bash
cd infra/platform/tf
terraform init
terraform validate
terraform fmt -recursive

# Pass 1 — Create all resources with placeholder IAM trust policy
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=false"
```

After Pass 1, retrieve the Snowflake storage integration values:

```sql
DESC INTEGRATION S3_STORAGE_INTEGRATION;
-- Copy STORAGE_AWS_IAM_USER_ARN  → trust.snowflake_principal_arn in aws/config.json
-- Copy STORAGE_AWS_EXTERNAL_ID   → trust.snowflake_external_id   in aws/config.json
```

Update `input-jsons/aws/config.json` with these values, then:

```bash
# Pass 2 — Update IAM trust policy with real Snowflake values
terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=true"

# Verify storage integration is working
# Run in Snowflake: SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION('S3_STORAGE_INTEGRATION');

# Pass 3 — Enable Snowpipe auto-ingest
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=true"
```

---

### 6. Upload Source Data

```bash
aws s3 cp data/ s3://northbridge-raw-data/raw-data/json/ --recursive --include "*.json"
```

Snowpipe (`RAW_NORTHBRIDGE_PIPE`) auto-ingests files into `BRONZE.RAW_NORTHBRIDGE` within seconds of upload via S3 event notification → SQS.

---

### 7. Verify the Pipeline

```sql
-- BRONZE: check raw ingestion
SELECT COUNT(*) FROM NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;
-- Expected: 25,000

-- SILVER: check dynamic table refresh
SELECT COUNT(*) FROM NORTHBRIDGE_DATABASE.SILVER.CLEAN_NORTHBRIDGE_DT;

-- GOLD: check fact table population
SELECT COUNT(*) FROM NORTHBRIDGE_DATABASE.GOLD.FACT_TRANSACTIONS;
-- Expected: ~312,000

-- Check Snowpipe status
SELECT SYSTEM$PIPE_STATUS('NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE_PIPE');
```

---

### 8. Deploy the Streamlit Dashboard

Upload `app/northbridge_dashboard.py` via the Snowflake console:

**Projects → Streamlit → + Streamlit App** → select `STREAMLIT_WH` and schema `NORTHBRIDGE_DATABASE.STREAMLIT`

---

## Snowflake Objects

### Roles

| Role | Privilege | Used by |
| --- | --- | --- |
| `DB_PROVISIONER` | `CREATE DATABASE` on account | `module.database_schemas` |
| `WAREHOUSE_PROVISIONER` | `CREATE WAREHOUSE`, `MONITOR USAGE` on account | `module.warehouse` |
| `DATA_OBJECT_PROVISIONER` | `CREATE TABLE`, `CREATE FILE FORMAT`, `CREATE DYNAMIC TABLE`, `CREATE VIEW`, `CREATE FUNCTION` on schemas | `module.table`, `module.file_formats`, `module.dynamic_table` |
| `INGEST_OBJECT_PROVISIONER` | `CREATE INTEGRATION` on account; `CREATE STAGE`, `CREATE PIPE` on schemas | `module.storage_integrations`, `module.stage`, `module.pipe` |
| `NORTHBRIDGE_ANALYST` | `SELECT` on GOLD tables/views; `USAGE` on GOLD functions | Dashboard users |

### Warehouses

| Name | Size | Purpose |
| --- | --- | --- |
| `LOAD_WH` | MEDIUM | Snowpipe ingestion + COPY operations |
| `TRANSFORM_WH` | X-SMALL | Stream tasks, BRONZE → SILVER → GOLD |
| `STREAMLIT_WH` | X-SMALL | Dashboard queries |
| `ADHOC_WH` | X-SMALL | Development + ad-hoc debugging |

All warehouses: `auto_resume = true`, `auto_suspend = 60s`, `initially_suspended = true`.

### Schemas

| Schema | Layer | Purpose |
| --- | --- | --- |
| `BRONZE` | Raw | Landing zone — VARIANT JSON, audit columns |
| `SILVER` | Cleansed | Typed, deduplicated, validated dynamic table |
| `GOLD` | Curated | Fact & dimension tables, analytical views, UDFs |
| `STREAMLIT` | Serving | Presentation layer for dashboard |

---

## Streamlit Dashboard

Five tabs backed by `GOLD` views, with sidebar filters for Customer Segment, Risk Rating, and Region.

| Tab | Key visuals |
| --- | --- |
| Executive KPIs | AUM, NPL ratio, avg credit score, AUM treemap by region |
| Customer Insights | Income & credit score distributions, segment and employment mix |
| Loan Portfolio | Loan book by type, status distribution, rate vs amount scatter |
| Transactions | Monthly volume trend, channel mix, failed transaction trend |
| Risk & Compliance | KYC status, AML exposure, credit tier vs risk heatmap |

---

## Dataset

| Metric | Value |
| --- | --- |
| Customers | 25,000 |
| Total nested records | ~495,000 |
| Accounts | ~75,000 |
| Loans | ~35,000 |
| Transactions | ~312,000 |
| JSON schema version | 3.0 |
| Transaction date range | 2022–2024 |
| Total file size | ~329 MB (5 × ~66 MB parts) |

Each customer record contains 9 nested objects: `accounts[]`, `loans[]`, `credit_cards[]`, `transactions[]`, `alerts[]`, `digital_profile{}`, `compliance{}`, `financial_summary{}`, `employment{}`.

To regenerate the synthetic dataset (deterministic, seed `2025`):

```bash
python3 scripts/gen_large.py
```

---

## Domain Glossary

| Term | Definition |
| --- | --- |
| AUM | Assets Under Management — total deposit balances |
| NPL Ratio | Non-Performing Loan ratio — at-risk loan value / total loan book |
| KYC | Know Your Customer — `Verified`, `Pending`, `Flagged`, `Expired` |
| AML | Anti-Money Laundering — risk score 0–100 |
| PEP | Politically Exposed Person |
| EMI | Equated Monthly Instalment |
| At-Risk Loan | Loan with status `Defaulted` or `Delinquent` |
| SiS | Streamlit in Snowflake |

---

## Teardown

```bash
cd infra/platform/tf
terraform destroy -var-file="terraform.tfvars"
```

> Ensure S3 buckets are empty before destroying. If the bucket has versioned objects, set `force_destroy: true` in `input-jsons/aws/config.json` first, then apply, then destroy.

---

## License

MIT
