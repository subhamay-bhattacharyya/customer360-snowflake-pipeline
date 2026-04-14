# Snowflake Dynamic Table Tutorial

![Built with Kiro](https://img.shields.io/badge/Built_with-Kiro-8845f4?logo=robot&logoColor=white)&nbsp;![Commit Activity](https://img.shields.io/github/commit-activity/t/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Last Commit](https://img.shields.io/github/last-commit/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Release Date](https://img.shields.io/github/release-date/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Repo Size](https://img.shields.io/github/repo-size/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![File Count](https://img.shields.io/github/directory-file-count/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Issues](https://img.shields.io/github/issues/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Top Language](https://img.shields.io/github/languages/top/subhamay-bhattacharyya/customer360-snowflake-pipeline)&nbsp;![Custom Endpoint](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bsubhamay/62c0119f3568e2b8e12f9b1b9cd1c80d/raw/customer360-snowflake-pipeline.json?)

A hands-on tutorial for Snowflake Dynamic Tables with Infrastructure as Code (Terraform) and automated deployment using GitHub Actions.

## Overview

This tutorial demonstrates Snowflake Dynamic Tables - a declarative data transformation feature that automatically refreshes based on changes in underlying base tables. The project includes:

- **HRMS Database**: Sample HR schema with EMPLOYEES, DEPARTMENTS, and related tables
- **Dynamic Tables**: Three variations demonstrating different TARGET_LAG and INITIALIZE options
- **Infrastructure as Code**: Terraform configurations for Snowflake resources
- **Seed Data**: Sample data for testing dynamic table behavior

## Dynamic Tables - Key Concepts

Dynamic Tables provide declarative data transformation pipelines with automatic refresh capabilities. Key parameters:

| Parameter    | Options                                           | Description                                                       |
| ------------ | ------------------------------------------------- | ----------------------------------------------------------------- |
| TARGET_LAG   | Time interval (e.g., '60 minutes') or 'DOWNSTREAM'| Maximum staleness allowed for the dynamic table data              |
| REFRESH_MODE | AUTO, FULL, INCREMENTAL                           | How the table refreshes (AUTO tries INCREMENTAL first, then FULL) |
| INITIALIZE   | ON_CREATE, ON_SCHEDULE                            | When to populate the table initially                              |
| WAREHOUSE    | Warehouse name                                    | Required compute resource for refresh operations                  |

## Dynamic Table SQL Reference

### Use Case 1: Create Dynamic Table with ON_SCHEDULE Initialize

```sql
-- Dynamic table that waits for scheduled refresh before populating
USE DATABASE HRMS;
USE SCHEMA HR;

CREATE OR REPLACE DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_SCHEDULE
    TARGET_LAG = '60 minutes'
    WAREHOUSE = 'DYT_LAB_01_WH'
    REFRESH_MODE = AUTO               -- AUTO|FULL|INCREMENTAL
    INITIALIZE = ON_SCHEDULE          -- ON_SCHEDULE|ON_CREATE
AS
SELECT
    E.EMPLOYEE_ID,
    E.JOB_ID,
    E.MANAGER_ID,
    E.DEPARTMENT_ID,
    E.EMAIL,
    D.LOCATION_ID,
    E.FIRST_NAME,
    E.LAST_NAME,
    E.SALARY,
    E.COMMISSION_PCT,
    D.DEPARTMENT_NAME
FROM
    HRMS.HR.EMPLOYEES E
    INNER JOIN HRMS.HR.DEPARTMENTS D ON E.DEPARTMENT_ID = D.DEPARTMENT_ID;
```

> **Expected Behavior:** The dynamic table is created but remains empty initially. If you query it immediately after creation, you will get an error: "Dynamic Table is not initialized. Please run a manual refresh or wait for the scheduled refresh before querying." You must either wait up to 60 minutes for the first scheduled refresh or run a manual refresh:
>
> ```sql
> ALTER DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_SCHEDULE REFRESH;
> ```

### Use Case 2: Create Dynamic Table with ON_CREATE Initialize

```sql
-- Dynamic table that populates immediately upon creation
CREATE OR REPLACE DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_CREATE
    TARGET_LAG = '60 minutes'
    WAREHOUSE = 'DYT_LAB_01_WH'
    REFRESH_MODE = AUTO        -- AUTO|FULL|INCREMENTAL
    INITIALIZE = ON_CREATE     -- ON_SCHEDULE|ON_CREATE
AS
SELECT
    E.EMPLOYEE_ID,
    E.JOB_ID,
    E.MANAGER_ID,
    E.DEPARTMENT_ID,
    E.EMAIL,
    D.LOCATION_ID,
    E.FIRST_NAME,
    E.LAST_NAME,
    E.SALARY,
    E.COMMISSION_PCT,
    D.DEPARTMENT_NAME
FROM
    HRMS.HR.EMPLOYEES E
    INNER JOIN HRMS.HR.DEPARTMENTS D ON E.DEPARTMENT_ID = D.DEPARTMENT_ID;
```

> **Expected Behavior:** The dynamic table is created and immediately populated with data from the base tables. You can query it right away without errors. Subsequent refreshes occur automatically based on the 60-minute TARGET_LAG - meaning data can be up to 60 minutes stale before an automatic refresh is triggered.
>
> ```sql
> SELECT * FROM DT_EMP_DEPT_LAG_60_ON_CREATE;
> ```

### Use Case 3: Create Dynamic Table with DOWNSTREAM Target Lag

```sql
-- Dynamic table that only refreshes manually (no automatic refresh)
CREATE OR REPLACE DYNAMIC TABLE DT_EMP_DEPT_DOWNSTREAM_ON_CREATE
    TARGET_LAG = DOWNSTREAM
    WAREHOUSE = 'DYT_LAB_01_WH'
    REFRESH_MODE = AUTO          -- ON_SCHEDULE|ON_CREATE
    INITIALIZE = ON_CREATE       -- ON_SCHEDULE|ON_CREATE
AS
SELECT
    E.EMPLOYEE_ID,
    E.JOB_ID,
    E.MANAGER_ID,
    E.DEPARTMENT_ID,
    E.EMAIL,
    D.LOCATION_ID,
    E.FIRST_NAME,
    E.LAST_NAME,
    E.SALARY,
    E.COMMISSION_PCT,
    D.DEPARTMENT_NAME
FROM
    HRMS.HR.EMPLOYEES E
    INNER JOIN HRMS.HR.DEPARTMENTS D ON E.DEPARTMENT_ID = D.DEPARTMENT_ID;
```

> **Expected Behavior:** The dynamic table is created and immediately populated (due to ON_CREATE). However, changes to the base tables (EMPLOYEES, DEPARTMENTS) will NOT automatically propagate to this dynamic table. No matter how long you wait, the data remains stale until you manually refresh. Use DOWNSTREAM when you want full control over when data syncs occur.
>
> ```sql
> ALTER DYNAMIC TABLE DT_EMP_DEPT_DOWNSTREAM_ON_CREATE REFRESH;
> ```

### Query Dynamic Table

```sql
-- Select data from dynamic table
SELECT * FROM DT_EMP_DEPT_LAG_60_ON_CREATE;

-- Count rows
SELECT COUNT(*) FROM DT_EMP_DEPT_LAG_60_ON_CREATE;

-- Select specific employees
SELECT * FROM DT_EMP_DEPT_LAG_60_ON_CREATE WHERE EMPLOYEE_ID IN (100, 101);
```

> **Expected Behavior:** Returns the joined employee-department data. For ON_CREATE tables, data is available immediately. For ON_SCHEDULE tables, querying before the first refresh returns an error.

### Manual Refresh

```sql
-- Manually refresh the dynamic table
ALTER DYNAMIC TABLE DT_EMP_DEPT_DOWNSTREAM_ON_CREATE REFRESH;
```

> **Expected Behavior:** Forces an immediate refresh of the dynamic table. The STATISTICS column in the output shows the number of rows inserted, deleted, and copied. If there are no changes in the base tables since the last refresh, it shows "no new data". This is essential for DOWNSTREAM tables and useful for ON_SCHEDULE tables when you don't want to wait.

### Suspend and Resume

```sql
-- Suspend automatic refresh
ALTER DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_SCHEDULE SUSPEND;

-- Resume automatic refresh
ALTER DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_SCHEDULE RESUME;
```

> **Expected Behavior:** SUSPEND stops all automatic refresh operations - useful during maintenance on base tables (e.g., column changes, data type updates, bulk loads). The scheduling_state changes to "suspended". RESUME restarts automatic refresh and changes scheduling_state back to "running". Use `SHOW DYNAMIC TABLES` to verify the current state.

### Modify Dynamic Table Parameters

```sql
-- Change TARGET_LAG and WAREHOUSE
ALTER DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_SCHEDULE SET
    TARGET_LAG = '1 hour'
    WAREHOUSE = 'DYT_LAB_01_WH';
```

> **Expected Behavior:** Updates the dynamic table's refresh parameters without recreating it. You can change TARGET_LAG (e.g., from '60 minutes' to '1 hour' or to 'DOWNSTREAM') and WAREHOUSE. Use `SHOW DYNAMIC TABLES` to verify the new parameter values.

### View Dynamic Table Information

```sql
-- Show specific dynamic table
SHOW DYNAMIC TABLE LIKE 'DT_EMP_DEPT%';

-- Show all dynamic tables in schema
SHOW DYNAMIC TABLES;

-- Describe dynamic table structure
DESCRIBE DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_CREATE;
```

> **Expected Behavior:** SHOW returns metadata including: created_on, name, database, schema, rows, owner, target_lag, refresh_mode, warehouse, text (the AS query), and scheduling_state (running/suspended). DESCRIBE returns the column structure (names, data types, nullable, etc.) similar to describing a regular table.

### Drop Dynamic Table

```sql
DROP DYNAMIC TABLE DT_EMP_DEPT_LAG_60_ON_CREATE;
```

> **Expected Behavior:** Permanently removes the dynamic table. This is a standard DROP operation - the table and all its data are deleted. The base tables (EMPLOYEES, DEPARTMENTS) are unaffected.

### Test Data Changes with DOWNSTREAM

```sql
-- Update base table
UPDATE HRMS.HR.EMPLOYEES
SET EMAIL = EMAIL || '@GMAIL'
WHERE EMPLOYEE_ID IN (100, 101);

-- Check dynamic table (will show old values with DOWNSTREAM)
SELECT EMPLOYEE_ID, EMAIL FROM DT_EMP_DEPT_DOWNSTREAM_ON_CREATE WHERE EMPLOYEE_ID IN (100, 101);

-- Manual refresh to sync changes
ALTER DYNAMIC TABLE DT_EMP_DEPT_DOWNSTREAM_ON_CREATE REFRESH;

-- Verify changes are now reflected
SELECT EMPLOYEE_ID, EMAIL FROM DT_EMP_DEPT_DOWNSTREAM_ON_CREATE WHERE EMPLOYEE_ID IN (100, 101);
```

> **Expected Behavior:** After the UPDATE, querying the DOWNSTREAM dynamic table still shows the old EMAIL values ('SKING', 'NKOCHHAR'). The changes do NOT propagate automatically. After running REFRESH, the dynamic table syncs with the base table - internally it deletes the old rows and inserts new rows with updated values. The STATISTICS output shows "2 rows inserted" (the refresh mechanism deletes old + inserts new). Subsequent queries show the updated EMAIL values ('SKING@GMAIL', 'NKOCHHAR@GMAIL').

## Tutorial Use Cases

This tutorial implements three dynamic tables demonstrating different configurations:

| Dynamic Table                      | TARGET_LAG | INITIALIZE  | Use Case                                      |
| ---------------------------------- | ---------- | ----------- | --------------------------------------------- |
| DT_EMP_DEPT_LAG_60_ON_SCHEDULE     | 60 minutes | ON_SCHEDULE | Deferred initial load, automatic refresh      |
| DT_EMP_DEPT_LAG_60_ON_CREATE       | 60 minutes | ON_CREATE   | Immediate initial load, automatic refresh     |
| DT_EMP_DEPT_DOWNSTREAM_ON_CREATE   | DOWNSTREAM | ON_CREATE   | Manual refresh only, immediate initial load   |

## Repository Structure

```text
.
├── infra/snowflake/tf/           # Terraform configurations
│   ├── main.tf                   # Module orchestration
│   ├── locals.tf                 # Local variables and configurations
│   ├── variables.tf              # Input variables
│   ├── providers.tf              # Snowflake provider configuration
│   ├── seed-data/                # SQL seed data files
│   │   ├── seed.json             # Seed configuration
│   │   ├── employees.sql         # Employee data
│   │   ├── departments.sql       # Department data
│   │   └── ...                   # Other seed files
│   └── templates/dynamic-tables/ # Dynamic table query templates
│       └── dyt_emp_dept.tpl      # Employee-Department join query
├── input-jsons/snowflake/        # Configuration files
│   └── config.json               # Warehouse, database, table configs
├── CREATE_DDL_HRMS_HR.sql        # HRMS database DDL script
└── .github/workflows/            # GitHub Actions workflows
```

## Getting Started

### Prerequisites

- Snowflake Account with appropriate permissions
- Terraform >= 1.0
- GitHub Repository with Actions enabled

### 1. Generate RSA Key Pair for Snowflake Authentication

Snowflake uses RSA keypair authentication (JWT) instead of username/password. Generate the keys and store them in the `keypair/` directory (gitignored):

```bash
mkdir -p keypair && cd keypair

# Step 1 — Generate a 2048-bit RSA private key in PKCS#8 (unencrypted) format
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt

# Step 2 — Derive the public key
openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub

# Step 3 — Extract the public key body (strip headers and newlines) for Snowflake
grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC" | tr -d '\n'
```

Copy the output of Step 3 — you will need it in the next step.

### 2. Create Service Account and Roles in Snowflake

#### Setting Up Admin Roles

Run this SQL in Snowflake (replace `YOUR_PUBLIC_KEY_HERE` with the output from Step 1):

```sql
-- ============================================================================
-- Snowflake: GitHub Actions Service User + Core Automation Roles (Hardened)
--
-- Creates:
--   * User: GITHUB_ACTIONS_USER (key-pair auth; default role PUBLIC; no default WH)
--   * Roles:
--       - PLATFORM_DB_OWNER   (CREATE DATABASE)
--       - DATA_OBJECT_ADMIN   (no privileges granted here; typically schema-scoped later)
--       - INGEST_ADMIN        (no privileges granted here; typically integration/stage/pipe scoped later)
--       - WAREHOUSE_ADMIN     (CREATE WAREHOUSE)
--   * Grants all roles to the GitHub Actions user
--
-- Run as: SECURITYADMIN (recommended)
-- Replace:
--   - RSA_PUBLIC_KEY value below
-- ============================================================================

USE ROLE SECURITYADMIN;

-- ----------------------------------------------------------------------------
-- 1) Create Roles
-- ----------------------------------------------------------------------------
CREATE ROLE IF NOT EXISTS PLATFORM_DB_OWNER;
CREATE ROLE IF NOT EXISTS DATA_OBJECT_ADMIN;
CREATE ROLE IF NOT EXISTS INGEST_ADMIN;
CREATE ROLE IF NOT EXISTS WAREHOUSE_ADMIN;

-- ----------------------------------------------------------------------------
-- 2) Grant Account-level Privileges (only where applicable)
-- ----------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;
-- PLATFORM_DB_OWNER: create databases (account-level)
GRANT CREATE DATABASE ON ACCOUNT TO ROLE PLATFORM_DB_OWNER;


-- WAREHOUSE_ADMIN: create warehouses (account-level)
GRANT CREATE WAREHOUSE ON ACCOUNT TO ROLE WAREHOUSE_ADMIN;

-- Optional but recommended: allow visibility into account/warehouse usage
GRANT MONITOR USAGE ON ACCOUNT TO ROLE WAREHOUSE_ADMIN;
GRANT USAGE ON WAREHOUSE UTIL_WH TO ROLE WAREHOUSE_ADMIN;
GRANT CREATE INTEGRATION ON ACCOUNT TO ROLE INGEST_ADMIN;

-- NOTE:
-- DATA_OBJECT_ADMIN and INGEST_ADMIN are intentionally left with NO privileges here.
-- They should be granted schema/database/integration-specific privileges later in Terraform,
-- once the target database/schema/integrations exist (JSON-driven).

-- ----------------------------------------------------------------------------
-- 3) Create GitHub Actions Service User (Key-Pair Auth Only)
-- ----------------------------------------------------------------------------
CREATE USER IF NOT EXISTS GITHUB_ACTIONS_USER
  LOGIN_NAME           = 'GITHUB_ACTIONS_USER'
  DISPLAY_NAME         = 'GitHub Actions Service User'
  DEFAULT_ROLE         = PUBLIC
  DEFAULT_WAREHOUSE    = NULL
  MUST_CHANGE_PASSWORD = FALSE
  DISABLED             = FALSE
  RSA_PUBLIC_KEY       = 'YOUR_PUBLIC_KEY_HERE';

-- ----------------------------------------------------------------------------
-- 4) Grant Roles to GitHub Actions User (NOT default)
-- ----------------------------------------------------------------------------
GRANT ROLE PLATFORM_DB_OWNER TO USER GITHUB_ACTIONS_USER;
GRANT ROLE DATA_OBJECT_ADMIN TO USER GITHUB_ACTIONS_USER;
GRANT ROLE INGEST_ADMIN      TO USER GITHUB_ACTIONS_USER;
GRANT ROLE WAREHOUSE_ADMIN   TO USER GITHUB_ACTIONS_USER;

-- ----------------------------------------------------------------------------
-- 5) Verification
-- ----------------------------------------------------------------------------
SHOW USERS LIKE 'GITHUB_ACTIONS_USER';
SHOW GRANTS TO USER GITHUB_ACTIONS_USER;
SHOW GRANTS TO ROLE PLATFORM_DB_OWNER;
SHOW GRANTS TO ROLE DATA_OBJECT_ADMIN;
SHOW GRANTS TO ROLE INGEST_ADMIN;
SHOW GRANTS TO ROLE WAREHOUSE_ADMIN;
```

#### Setting Up Analyst Role (Read-Only)

Run the following SQL as `ACCOUNTADMIN` to create a read-only analyst role:

```sql
-- ============================================================================
-- Create Analyst Role for Read-Only Access
-- ============================================================================

-- 1. Create the analyst role
CREATE ROLE IF NOT EXISTS ANALYST
  COMMENT = 'Read-only access to query tables and views';

-- 2. Set up role hierarchy (ANALYST reports to SYSADMIN)
GRANT ROLE ANALYST TO ROLE SYSADMIN;

-- 3. Grant warehouse usage for query execution
GRANT USAGE ON WAREHOUSE COMPUTE_WH TO ROLE ANALYST;

-- 4. Grant database and schema usage (read-only)
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE ANALYST;
GRANT USAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

-- 5. Grant SELECT on all existing tables in schema
GRANT SELECT ON ALL TABLES IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

-- 6. Grant SELECT on all existing views in schema
GRANT SELECT ON ALL VIEWS IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

-- 7. Grant SELECT on future tables (auto-grant for new tables)
GRANT SELECT ON FUTURE TABLES IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

-- 8. Grant SELECT on future views (auto-grant for new views)
GRANT SELECT ON FUTURE VIEWS IN SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE ANALYST;

-- 9. Grant role to analyst users
GRANT ROLE ANALYST TO USER <ANALYST_USERNAME>;
```

#### Post-Database Creation Grants

After databases and schemas are created by `PLATFORM_DB_ADMIN`, run these grants:

```sql
-- Grant schema privileges to DATA_OBJECT_ADMIN
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT USAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE FILE FORMAT ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;
GRANT CREATE TABLE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE DATA_OBJECT_ADMIN;

-- Grant schema privileges to INGEST_ADMIN
GRANT USAGE ON DATABASE <DATABASE_NAME> TO ROLE INGEST_ADMIN;
GRANT USAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;
GRANT CREATE STAGE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;
GRANT CREATE PIPE ON SCHEMA <DATABASE_NAME>.<SCHEMA_NAME> TO ROLE INGEST_ADMIN;
```

**Security Notes:**
- Use `SYSADMIN` role for all DDL and grant operations
- Grant `MANAGE GRANTS` privilege to SYSADMIN for permission management
- Key-pair authentication is more secure than passwords
- Service accounts provide better audit trails
- Never commit private keys to the repository

To verify the key was assigned correctly:

```sql
DESC USER GITHUB_ACTIONS_USER;
-- Look for RSA_PUBLIC_KEY_FP — it should show a fingerprint like SHA256:...
```

To rotate the key later, generate a new keypair and run:

```sql
ALTER USER GITHUB_ACTIONS_USER SET RSA_PUBLIC_KEY = '<new public key body>';
```

### 3. Configure HCP Terraform Variable Set

Variables are split between the **HCP Variable Set** and **per-environment `.tfvars` files** based on scope:

- **HCP Variable Set** — secrets and account-level values that are the **same across all environments** (devl, test, prod). These should not be checked into version control.
- **Per-environment `.tfvars` files** — non-sensitive, environment-specific values that **vary between environments** (e.g. role names, warehouse names, config paths). These live in `infra/platform/tf/environments/{devl,test,prod}/terraform.tfvars`.

#### HCP Variable Set (account-level secrets and constants)

In your HCP Terraform workspace, create a **Variable Set** with the following variables:

| Variable Name                        | Category    | Sensitive | Description                                                        |
| ------------------------------------ | ----------- | --------- | ------------------------------------------------------------------ |
| `SNOWFLAKE_PRIVATE_KEY`              | Environment | Yes       | Full PEM content of the private key file (including BEGIN/END headers) |
| `TF_VAR_snowflake_organization_name` | Environment | No        | Snowflake organization name (from `SELECT CURRENT_ORGANIZATION_NAME()`) |
| `TF_VAR_snowflake_account_name`      | Environment | No        | Snowflake account name (from `SELECT CURRENT_ACCOUNT_NAME()`)      |
| `TF_VAR_snowflake_user`              | Environment | No        | Snowflake service account username                                 |
| `AWS_ACCESS_KEY_ID`                  | Environment | Yes       | AWS access key for the deployment IAM user                         |
| `AWS_SECRET_ACCESS_KEY`              | Environment | Yes       | AWS secret key for the deployment IAM user                         |

> **Note on `SNOWFLAKE_PRIVATE_KEY`:** This is an **environment variable** (not a Terraform variable). The Snowflake provider reads it directly from the environment — no `TF_VAR_` prefix needed. Paste the **full PEM content** of `keypair/snowflake_key.p8` including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` headers with all newlines. Do **not** include the trailing `%` character that some terminals display — that is just a shell indicator, not part of the key.

#### Per-environment `.tfvars` files (environment-specific values)

These variables live in `infra/platform/tf/environments/{devl,test,prod}/terraform.tfvars` and are checked into version control. They can differ across environments:

| Variable Name                    | Description                                        | Example (devl)                |
| -------------------------------- | -------------------------------------------------- | ----------------------------- |
| `db_provisioner_role`            | Role for database/schema ops                       | `PLATFORM_DB_OWNER`           |
| `warehouse_provisioner_role`     | Role for warehouse ops                             | `WAREHOUSE_ADMIN`             |
| `data_object_provisioner_role`   | Role for table/file format ops                     | `DATA_OBJECT_ADMIN`           |
| `ingest_object_provisioner_role` | Role for stage/pipe ops                            | `INGEST_ADMIN`                |
| `snowflake_warehouse`            | Default warehouse for Terraform ops                | `UTIL_WH`                     |
| `aws_config_path`               | Path to environment-specific AWS config JSON       | `config/aws/devl/config.json` |
| `snowflake_config_path`         | Path to environment-specific Snowflake config JSON | `config/snowflake/devl/config.json` |
| `project_code`                   | Project code prefix for resource naming            | `cust360sf`                   |

### 4. Configure Local Terraform Variables

For local development, copy the environment-specific tfvars file:

```bash
cd infra/platform/tf
cp environments/devl/terraform.tfvars terraform.tfvars
```

Set the Snowflake connection variables as environment variables (these would normally come from the HCP Variable Set):

```bash
export SNOWFLAKE_PRIVATE_KEY="$(cat ../../keypair/snowflake_key.p8)"
export TF_VAR_snowflake_organization_name="YOUR_ORG"
export TF_VAR_snowflake_account_name="YOUR_ACCOUNT"
export TF_VAR_snowflake_user="GITHUB_ACTIONS_USER"
```

### 5. Deploy Infrastructure

```bash
cd infra/platform/tf
terraform init
terraform plan -var-file="terraform.tfvars"
terraform apply -var-file="terraform.tfvars"
```

## HRMS Database Schema

The tutorial uses an HRMS (Human Resource Management System) database with the following tables:

| Table       | Description                                          |
| ----------- | ---------------------------------------------------- |
| EMPLOYEES   | Employee information (ID, name, email, salary, etc.) |
| DEPARTMENTS | Department details (ID, name, manager, location)     |
| LOCATIONS   | Office locations                                     |
| COUNTRIES   | Country reference data                               |
| REGIONS     | Geographic regions                                   |
| JOBS        | Job titles and salary ranges                         |
| JOB_HISTORY | Employee job history                                 |

## Key Learnings

1. **TARGET_LAG** controls how stale the data can be before refresh
2. **INITIALIZE = ON_CREATE** populates immediately; **ON_SCHEDULE** waits for first scheduled refresh
3. **TARGET_LAG = DOWNSTREAM** requires manual refresh - useful for controlled updates
4. **REFRESH_MODE = AUTO** is recommended - tries INCREMENTAL first, falls back to FULL
5. Dynamic tables cannot be directly TRUNCATED or UPDATED - data comes only from base tables
6. Use **SUSPEND/RESUME** during maintenance on base tables

## License

MIT License - See [LICENSE](LICENSE) for details.

## References

- [Snowflake Dynamic Tables Documentation](https://docs.snowflake.com/en/user-guide/dynamic-tables)
- [Snowflake Master Class for Data Engineers - Udemy](https://www.udemy.com/)
