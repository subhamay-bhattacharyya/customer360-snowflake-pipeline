# Snowflake Dynamic Table Tutorial

![Built with Kiro](https://img.shields.io/badge/Built_with-Kiro-8845f4?logo=robot&logoColor=white)&nbsp;![Commit Activity](https://img.shields.io/github/commit-activity/t/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Last Commit](https://img.shields.io/github/last-commit/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Release Date](https://img.shields.io/github/release-date/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Repo Size](https://img.shields.io/github/repo-size/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![File Count](https://img.shields.io/github/directory-file-count/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Issues](https://img.shields.io/github/issues/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Top Language](https://img.shields.io/github/languages/top/subhamay-bhattacharyya/snowflake-dynamic-table-tutorial)&nbsp;![Custom Endpoint](https://img.shields.io/endpoint?url=https://gist.githubusercontent.com/bsubhamay/62c0119f3568e2b8e12f9b1b9cd1c80d/raw/snowflake-dynamic-table-tutorial.json?)

A hands-on tutorial for Snowflake Dynamic Tables with Infrastructure as Code (Terraform) and automated deployment using GitHub Actions.

## Overview

This tutorial demonstrates Snowflake Dynamic Tables - a declarative data transformation feature that automatically refreshes based on changes in underlying base tables. The project includes:

- **HRMS Database**: Sample HR schema with EMPLOYEES, DEPARTMENTS, and related tables
- **Dynamic Tables**: Three variations demonstrating different TARGET_LAG and INITIALIZE options
- **Infrastructure as Code**: Terraform configurations for Snowflake resources
- **Seed Data**: Sample data for testing dynamic table behavior

## Dynamic Tables - Key Concepts

Dynamic Tables provide declarative data transformation pipelines with automatic refresh capabilities. Key parameters:

| Parameter | Options | Description |
|-----------|---------|-------------|
| TARGET_LAG | Time interval (e.g., '60 minutes') or 'DOWNSTREAM' | Maximum staleness allowed for the dynamic table data |
| REFRESH_MODE | AUTO, FULL, INCREMENTAL | How the table refreshes (AUTO tries INCREMENTAL first, then FULL) |
| INITIALIZE | ON_CREATE, ON_SCHEDULE | When to populate the table initially |
| WAREHOUSE | Warehouse name | Required compute resource for refresh operations |

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

| Dynamic Table | TARGET_LAG | INITIALIZE | Use Case |
|---------------|------------|------------|----------|
| DT_EMP_DEPT_LAG_60_ON_SCHEDULE | 60 minutes | ON_SCHEDULE | Deferred initial load, automatic refresh |
| DT_EMP_DEPT_LAG_60_ON_CREATE | 60 minutes | ON_CREATE | Immediate initial load, automatic refresh |
| DT_EMP_DEPT_DOWNSTREAM_ON_CREATE | DOWNSTREAM | ON_CREATE | Manual refresh only, immediate initial load |

## Repository Structure

```
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

### 1. Configure Snowflake Authentication

Set up key-pair authentication for Terraform:

```bash
# Generate RSA key pair
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_key.p8 -nocrypt
openssl rsa -in snowflake_key.p8 -pubout -out snowflake_key.pub

# Extract public key for Snowflake
grep -v "BEGIN PUBLIC" snowflake_key.pub | grep -v "END PUBLIC" | tr -d '\n'
```

### 2. Create Service Account in Snowflake

```sql
CREATE USER IF NOT EXISTS GITHUB_ACTIONS_USER
  RSA_PUBLIC_KEY = 'YOUR_PUBLIC_KEY_HERE'
  DEFAULT_ROLE = SYSADMIN
  COMMENT = 'Service account for Terraform deployments';

GRANT ROLE SYSADMIN TO USER GITHUB_ACTIONS_USER;
```

### 3. Configure Terraform Variables

Update `infra/snowflake/tf/terraform.tfvars`:

```hcl
snowflake_organization_name  = "YOUR_ORG"
snowflake_account_name       = "YOUR_ACCOUNT"
snowflake_user               = "GITHUB_ACTIONS_USER"
db_provisioner_role          = "PLATFORM_DB_OWNER"
warehouse_provisioner_role   = "WAREHOUSE_ADMIN"
data_object_provisioner_role = "DATA_OBJECT_ADMIN"
snowflake_warehouse          = "UTIL_WH"
enable_seed_data             = true
```

### 4. Deploy Infrastructure

```bash
cd infra/snowflake/tf
terraform init
terraform plan
terraform apply
```

## HRMS Database Schema

The tutorial uses an HRMS (Human Resource Management System) database with the following tables:

| Table | Description |
|-------|-------------|
| EMPLOYEES | Employee information (ID, name, email, salary, etc.) |
| DEPARTMENTS | Department details (ID, name, manager, location) |
| LOCATIONS | Office locations |
| COUNTRIES | Country reference data |
| REGIONS | Geographic regions |
| JOBS | Job titles and salary ranges |
| JOB_HISTORY | Employee job history |

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
