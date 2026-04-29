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

All AWS and Snowflake infrastructure is provisioned via **Terraform** with a config-driven approach — resource names come from `infra/platform/tf/config/` and are never hardcoded in `.tf` files.

---

## Architecture

### Data Pipeline

```mermaid
flowchart TD
    S3[("S3<br/>northbridge-raw-data/raw-data/json/")]
    SQS{{"SQS event notification<br/>s3:ObjectCreated:*"}}
    PIPE["Snowpipe auto-ingest<br/>RAW_NORTHBRIDGE_PIPE"]

    subgraph BRONZE["BRONZE — Raw"]
      RAW["RAW_NORTHBRIDGE<br/>VARIANT + audit columns<br/>25,000 records"]
    end

    subgraph SILVER["SILVER — Cleansed"]
      CLEAN["CLEAN_NORTHBRIDGE_DT<br/>Dynamic Table — typed &amp; cleansed"]
    end

    subgraph GOLD["GOLD — Curated"]
      DIMS["Dimensions<br/>DIM_CUSTOMER · DIM_BRANCH<br/>DIM_PRODUCT · DIM_DATE"]
      FACTS["Facts<br/>FACT_TRANSACTIONS · FACT_LOANS<br/>FACT_ACCOUNT_BALANCES"]
      VIEWS["Views<br/>V_KPI_SUMMARY · V_SEGMENT_STATS<br/>V_LOAN_PORTFOLIO · V_MONTHLY_TXN_TRENDS<br/>V_REGIONAL_PERF · V_RISK_DISTRIBUTION"]
    end

    subgraph SERVE["STREAMLIT — Serving"]
      DASH["Customer 360 Dashboard<br/>5 tabs · sidebar filters"]
    end

    S3 -->|"s3:ObjectCreated:*"| SQS
    SQS --> PIPE
    PIPE --> RAW
    RAW -->|"Dynamic Table auto-refresh<br/>target_lag = downstream"| CLEAN
    CLEAN -->|"Dynamic Tables + UDFs<br/>PROMINENT_INDEX · THREE_SUB_INDEX_CRITERIA · GET_INT"| DIMS
    CLEAN --> FACTS
    DIMS --> VIEWS
    FACTS --> VIEWS
    VIEWS -->|"Streamlit in Snowflake<br/>STREAMLIT_WH"| DASH
```

### Terraform Provisioning — 6 Phases

```mermaid
flowchart TD
    subgraph P1["Phase 1 — AWS Resources"]
      P1A["module.s3<br/>S3 bucket (landing zone)"]
      P1B["module.iam_role<br/>IAM role — trust policy computed from<br/>live storage integration output;<br/>account-root placeholder on first create"]
    end

    subgraph P2["Phase 2 — Snowflake Resources (strict dependency order)"]
      direction TB
      P2A["module.warehouse<br/>LOAD_WH · TRANSFORM_WH · STREAMLIT_WH · ADHOC_WH"]
      P2B["module.database_schemas<br/>NORTHBRIDGE_DATABASE + 4 schemas"]
      P2C["module.file_formats<br/>JSON_FILE_FORMAT"]
      P2D["module.storage_integrations<br/>S3_STORAGE_INTEGRATION"]
      P2E["module.api_integrations<br/>GitHub API integration — account-level;<br/>currently 0 resources (see caveat below)"]
      P2F["module.stage<br/>RAW_EXTERNAL_STG · RAW_INTERNAL_STG · STREAMLIT_STG"]
      P2G["module.table<br/>BRONZE.RAW_NORTHBRIDGE"]
      P2A --> P2B --> P2C --> P2D --> P2E --> P2F --> P2G
    end

    subgraph P3["Phase 3 — AWS Trust Policy Reconcile"]
      P3A["module.aws_iam_role_final<br/>Re-pushes live STORAGE_AWS_IAM_USER_ARN /<br/>STORAGE_AWS_EXTERNAL_ID to the IAM role<br/>on every apply (no manual flag — fires<br/>whenever a storage integration is configured)"]
    end

    subgraph P4["Phase 4 — Snowpipes (BRONZE layer)"]
      P4A["module.pipe<br/>RAW_NORTHBRIDGE_PIPE (auto_ingest=true)"]
      P4B["module.s3_notification<br/>S3 event → SQS wiring<br/>(enable_snowpipe_creation default true;<br/>set false only on the very first apply)"]
      P4A --> P4B
    end

    subgraph P5["Phase 5 — Dynamic Tables (SILVER + GOLD layers)"]
      direction TB
      P5A["module.dynamic_table<br/>SILVER.CLEAN_NORTHBRIDGE_DT"]
      P5B["module.dynamic_table_gold<br/>GOLD.DIM_CUSTOMER · DIM_PRODUCT · DIM_BRANCH<br/>GOLD.FACT_TRANSACTIONS · FACT_LOANS · FACT_ACCOUNT_BALANCES"]
      P5A --> P5B
    end

    subgraph P6["Phase 6 — Views (GOLD layer)"]
      direction TB
      P6A["module.views<br/>V_KPI_SUMMARY · V_SEGMENT_STATS · V_LOAN_PORTFOLIO<br/>V_MONTHLY_TXN_TRENDS · V_REGIONAL_PERF · V_RISK_DISTRIBUTION"]
      P6B["snowflake_grant_privileges_to_account_role.view_grants<br/>NORTHBRIDGE_ANALYST SELECT"]
      P6A --> P6B
    end

    P1 --> P2 --> P3 --> P4 --> P5 --> P6
```

> [!NOTE]
> **Streams and tasks are not used.** Ingestion is handled by Snowpipe
> (auto-ingest from S3); downstream refresh is handled by Dynamic Tables
> with `target_lag = "downstream"`.
> [!WARNING]
> **Module pin caveats** — known issues with the upstream modules pinned
> by this root module:
>
> | Module | Pin | Issue |
> | --- | --- | --- |
> | `module.api_integrations` | `feature/TFMOD-0001-…` | Awaiting a stable tag. Currently filters out the GitHub `git_https_api` entry because `snowflake_api_integration` does not accept that provider value. The correct resource for the Streamlit-deploy use case is a Git integration (`snowflake_git_repository`) — **not yet wired**. |
> | `module.views` | `feature/TFMOD-0007-…` | Awaiting a stable tag. Its `versions.tf` must be upgraded from `Snowflake-Labs/snowflake < 1.0.0` to `snowflakedb/snowflake >= 1.0.0` before `terraform init` will resolve. |

---

## Repository Structure

```text
customer360-snowflake-pipeline/
├── README.md
├── CLAUDE.md                                   # Claude Code project context
├── CHANGELOG.md                                # Auto-generated by git-cliff
├── CONTRIBUTING.md
├── CODE_OF_CONDUCT.md
├── LICENSE
├── PROMPT.md                                   # Claude Code prompt for config generation
├── cliff.toml                                  # git-cliff configuration
├── env.json
├── northbridge_customer360_architecture.svg    # Architecture diagram (vector)
├── project-architecture.jpg                    # Architecture diagram (raster)
│
├── .claude/
│   └── skills/                                 # Project-local Claude Code skills
│       ├── aws-config-iam-policies/
│       ├── aws-config-s3/
│       ├── aws-config-trust/
│       ├── github-readme/
│       ├── snowflake-config-dynamic-tables-functions/
│       ├── snowflake-config-snowpipes/
│       ├── snowflake-config-stages-fileformats/
│       ├── snowflake-config-tables/
│       └── tf-{backend,locals,main,outputs,providers,variables,versions}/
│
├── .devcontainer/                              # Dev container definition
├── .editorconfig
├── .gitignore
├── .github/
│   └── workflows/
│       ├── ci.yaml                             # Terraform fmt / validate / security scans
│       ├── terraform-deploy.yaml               # Provision infra (Pass A → Pass B)
│       ├── terraform-destroy.yaml              # Tear down infra
│       ├── deploy-streamlit-app.yaml           # Refresh Streamlit app from this repo
│       ├── create-branch.yaml
│       ├── setup-project.yaml
│       └── notify.yaml
│
├── app/
│   └── northbridge_dashboard.py                # Streamlit in Snowflake dashboard
│
├── data/                                       # Synthetic source dataset (~329 MB across 6 parts)
│   └── northbridge_part0{0..5}_of_05.json
│
├── documentation/
│   └── NorthBridge Bank Unified Data Lake for Customer 360.pptx
│
├── keypair/                                    # RSA keypair — GITIGNORED
│   ├── snowflake_key.p8                        # Private key — never commit
│   └── snowflake_key.pub                       # Public key
│
├── post-deployment-validation/
│   ├── create-gold-views.sql
│   └── pipe-validation.sql
│
└── infra/platform/tf/                          # Terraform root module
    ├── main.tf                                 # 6-phase orchestration
    ├── variables.tf
    ├── locals.tf
    ├── outputs.tf
    ├── validations.tf
    ├── backend.tf                              # HCP Terraform remote state
    ├── providers-aws.tf
    ├── providers-snowflake.tf                  # Multiple Snowflake provider aliases
    ├── versions.tf
    ├── modules/
    │   └── iam_role_final/                     # Local module — re-pushes IAM trust at apply time
    │       ├── main.tf
    │       ├── variables.tf
    │       └── outputs.tf
    ├── config/                                 # JSON-driven resource definitions
    │   ├── aws/
    │   │   └── {devl,test,prod}/config.json
    │   └── snowflake/
    │       ├── config.json                     # Default / shared config
    │       └── {devl,test,prod}/config.json
    ├── environments/
    │   └── {devl,test,prod}/terraform.tfvars
    └── templates/
        ├── bucket-policy/
        │   └── s3-bucket-policy.tpl
        ├── dynamic-tables/
        │   ├── clean_northbridge.tpl           # SILVER cleansing
        │   ├── dim_customer.tpl                # GOLD customer dimension
        │   ├── dim_product.tpl                 # GOLD product dimension
        │   ├── dim_branch.tpl                  # GOLD branch dimension
        │   ├── fact_transactions.tpl           # GOLD transaction fact
        │   ├── fact_loans.tpl                  # GOLD loan fact
        │   └── fact_account_balances.tpl       # GOLD account balance fact
        ├── views/
        │   ├── v_kpi_summary.tpl               # GOLD KPI summary view
        │   ├── v_loan_portfolio.tpl            # GOLD loan portfolio view
        │   ├── v_monthly_txn_trends.tpl        # GOLD monthly transaction trends
        │   ├── v_regional_perf.tpl             # GOLD regional performance
        │   ├── v_risk_distribution.tpl         # GOLD risk distribution
        │   └── v_segment_stats.tpl             # GOLD customer segment stats
        └── snowpipe-copy-statements/
            └── raw_northbridge_copy.tpl
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

# Step 4 — Produce the HCP Terraform value for `snowflake_private_key`
#          (base64-encodes the ENTIRE .p8 file — do NOT strip headers/newlines)
base64 < snowflake_key.p8 | tr -d '\n'
```

Copy the output of **Step 3** — you will paste this into the `RSA_PUBLIC_KEY` clause of `CREATE USER` in §2a.

Copy the output of **Step 4** — you will paste this (a single line, no trailing newline) into the `snowflake_private_key` Terraform variable in HCP in §3a. Do **not** strip the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` markers or the internal newlines from the key before encoding — `base64` encodes the file as-is and the Terraform provider decodes it back into a valid PEM at runtime via `base64decode()` in `providers-snowflake.tf`.

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
GRANT CREATE DYNAMIC TABLE ON SCHEMA NORTHBRIDGE_DATABASE.GOLD         TO ROLE DATA_OBJECT_PROVISIONER;

-- GOLD dynamic tables source from SILVER.CLEAN_NORTHBRIDGE_DT, so the role must be able to read it
GRANT SELECT ON ALL DYNAMIC TABLES    IN SCHEMA NORTHBRIDGE_DATABASE.SILVER TO ROLE DATA_OBJECT_PROVISIONER;
GRANT SELECT ON FUTURE DYNAMIC TABLES IN SCHEMA NORTHBRIDGE_DATABASE.SILVER TO ROLE DATA_OBJECT_PROVISIONER;

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
| `snowflake_private_key` | Terraform | No | ✅ Yes | `base64 < infra/platform/keypair/snowflake_key.p8 \| tr -d '\n'` (run from repo root; cross-platform — works on macOS and Linux) |
| `TF_VAR_snowflake_organization_name` | Environment | N/A | No | `SELECT CURRENT_ORGANIZATION_NAME();` in Snowflake |
| `TF_VAR_snowflake_account_name` | Environment | N/A | No | `SELECT CURRENT_ACCOUNT_NAME();` in Snowflake |
| `TF_VAR_snowflake_user` | Environment | N/A | No | `GITHUB_ACTIONS_USER` |

> **Important:**
>
> - For `snowflake_private_key` — set Category = **Terraform**, HCL = **unchecked**, Sensitive = **checked**. The value must be the base64-encoded **entire `.p8` file including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` markers and internal newlines**. The Terraform provider decodes it with `base64decode()` at runtime (see `providers-snowflake.tf:27`). Do **not** pre-strip the PEM headers or newlines — doing so yields raw DER bytes and JWT auth will fail.
> - For the three `TF_VAR_*` variables — set Category = **Environment**. HCP injects them as OS env vars and Terraform picks them up automatically.
> - Do **not** create `SNOWFLAKE_PRIVATE_KEY` as an environment variable — HCP strips newlines from env vars, breaking the PEM format.
> - When copying the base64 value, do **not** include any trailing `%` shown by your shell.

#### Verify the encoded private key round-trips

Before saving the HCP variable, round-trip the value locally and confirm the first decoded line is the PEM header:

```bash
base64 < infra/platform/keypair/snowflake_key.p8 | tr -d '\n' | base64 -d | head -1
# Expect exactly: -----BEGIN PRIVATE KEY-----
```

If the first line is anything else (garbled binary, or just a base64 blob), you either (a) stripped the PEM markers before encoding, (b) encoded the public key by mistake, or (c) the file is not PKCS#8 — regenerate per §1 and re-encode.

#### Avoid trailing whitespace on the three `TF_VAR_*` env vars

HCP Terraform silently preserves any trailing newline or CRLF pasted into an env-var field. A stray `\r\n` on `TF_VAR_snowflake_account_name`, `TF_VAR_snowflake_organization_name`, or `TF_VAR_snowflake_user` is URL-encoded into the Snowflake login URL at plan time and produces errors like:

```text
Error: open snowflake connection: parse
  "https://ORG-ACCOUNT%0D%0A.snowflakecomputing.com:443/...": invalid URL escape "%0D"
```

When saving these values in the HCP UI: clear the field completely, retype the value, and do **not** press Enter before clicking Save.

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
| `aws_config_path` | Path to AWS config JSON | `config/aws/devl/config.json` |
| `snowflake_config_path` | Path to Snowflake config JSON | `config/snowflake/devl/config.json` |
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

The IAM trust policy is reconciled at apply time from the live storage integration
output — there is no manual `DESC INTEGRATION` / config-edit step. On the very first
apply Snowpipe is gated off so it does not race the trust sync; every subsequent
apply runs in one pass.

```bash
cd infra/platform/tf
terraform init
terraform validate
terraform fmt -recursive

# Pass A — fresh bootstrap only. Creates core infra; IAM trust is auto-reconciled
# from the live storage integration output. Snowpipe is gated off so it doesn't
# race the trust sync on the first apply.
terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=false"

# Pass B — every subsequent apply. Default for enable_snowpipe_creation is true,
# so no flag is needed. This enables Snowpipe + S3 event notification.
terraform apply -var-file="terraform.tfvars"
```

> Optional sanity check after Pass A:
>
> ```sql
> SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION('S3_STORAGE_INTEGRATION');
> ```

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
| `DATA_OBJECT_PROVISIONER` | `CREATE TABLE`, `CREATE FILE FORMAT`, `CREATE DYNAMIC TABLE`, `CREATE VIEW`, `CREATE FUNCTION` on schemas | `module.table`, `module.file_formats`, `module.dynamic_table`, `module.dynamic_table_gold`, `module.views` |
| `INGEST_OBJECT_PROVISIONER` | `CREATE INTEGRATION` on account; `CREATE STAGE`, `CREATE PIPE` on schemas | `module.storage_integrations`, `module.api_integrations`, `module.stage`, `module.pipe` |
| `NORTHBRIDGE_ANALYST` | `SELECT` on GOLD tables/views; `USAGE` on GOLD functions | Dashboard users |

### Warehouses

| Name | Size | Purpose |
| --- | --- | --- |
| `LOAD_WH` | MEDIUM | Snowpipe ingestion + COPY operations |
| `TRANSFORM_WH` | X-SMALL | Dynamic Table refresh, BRONZE → SILVER → GOLD |
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
