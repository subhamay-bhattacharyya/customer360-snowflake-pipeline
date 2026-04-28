/* =============================================================================
   Pipeline Validation Script — CUST360 NorthBridge
   =============================================================================

   Purpose   : End-to-end validation of the S3 → Snowflake data pipeline,
               from storage integration through to GOLD analytics.

   Usage     : Execute top-to-bottom in a Snowsight SQL worksheet. Each
               phase builds on the previous one — do not skip ahead.

   Scope     : BRONZE (raw ingestion) → SILVER (cleansed) → GOLD (curated)
               across the CUST360_NORTHBRIDGE_DATABASE database.

   Resources : Storage Integration — CUST360_S3_STORAGE_INTEGRATION
               External Stage      — BRONZE.RAW_EXTERNAL_STG
               Snowpipe            — BRONZE.CUST360_RAW_NORTHBRIDGE_PIPE
               S3 Bucket           — cust360-northbridge-raw-data-devl-us-east-1

   Pre-reqs  : - Terraform infrastructure already deployed (all 3 passes)
               - AWS CLI configured for the target account
               - validate_all.txt uploaded to the bucket path (see Phase 1.2)
               - RSA keypair registered against the Snowflake user

   Conventions:
               - All SQL logic lives in .tpl files under
                 infra/platform/tf/templates/ — this script is a read-only
                 validation runbook, not a deployment artifact.
               - Resource names are defined in input-jsons/ — never hardcode
                 in .tf files.
               - This pipeline is read-only from Snowflake's perspective.
                 Do NOT grant s3:PutObject to the Snowflake IAM role.

   ============================================================================= */


/* =============================================================================
   PHASE 0 — Quick Open in Snowsight via GitHub API Integration
   =============================================================================

   This phase sets up a Snowflake Git integration so this validation script
   can be opened directly from Snowsight workspaces without copy/paste.

   Run this ONCE per Snowflake account. Subsequent pipeline checks can then
   open this file via:
     Snowsight → Projects → Workspaces → From Git Repository

   Prerequisites:
     - Your repo must be accessible (public, or provide a PAT secret)
     - Run as ACCOUNTADMIN (or a role with CREATE INTEGRATION privilege)

   ============================================================================= */

USE ROLE ACCOUNTADMIN;

-- Step 0.1 — Create API integration for Git access
--             Replace the api_allowed_prefixes value with your org/repo URL.
CREATE OR REPLACE API INTEGRATION CUST360_GITHUB_API_INTEGRATION
  API_PROVIDER         = GIT_HTTPS_API
  API_ALLOWED_PREFIXES = ('https://github.com/subhamay-bhattacharyya/customer360-snowflake-pipeline')
  ENABLED              = TRUE
  COMMENT              = 'GitHub integration for opening validation scripts in Snowsight';

-- Step 0.2 — (Optional) Store a Personal Access Token for private repos
--             Skip this block if the repo is public.
CREATE OR REPLACE SECRET CUST360_GITHUB_PAT
  TYPE     = PASSWORD
  USERNAME = '<your-github-username>'
  PASSWORD = '<your-github-pat>'
  COMMENT  = 'GitHub PAT for private repo access';

-- Step 0.3 — Create the Git repository reference in Snowflake
CREATE OR REPLACE GIT REPOSITORY CUST360_NORTHBRIDGE_DATABASE.PUBLIC.CUST360
  API_INTEGRATION = CUST360_GITHUB_API_INTEGRATION
  -- GIT_CREDENTIALS = CUST360_GITHUB_PAT   -- Uncomment if using a private repo
  ORIGIN          = 'https://github.com/<your-org>/aws-snowflake-e2e-project.git';

-- Step 0.4 — Fetch latest refs from the remote
ALTER GIT REPOSITORY CUST360_NORTHBRIDGE_DATABASE.PUBLIC.CUST360_SNOWFLAKE_PIPELINE FETCH;

-- Step 0.5 — Verify the repo is browsable
SHOW GIT BRANCHES IN GIT REPOSITORY CUST360_NORTHBRIDGE_DATABASE.PUBLIC.CUST360_SNOWFLAKE_PIPELINE;

-- Step 0.6 — Open this file directly in a Snowsight workspace:
--             Snowsight → Projects → Workspaces → + Workspace →
--             From Git Repository → select
--             CUST360_NORTHBRIDGE_DATABASE.PUBLIC.CUST360_SNOWFLAKE_PIPELINE →
--             navigate to the path where this .sql file is committed.


/* =============================================================================
   PHASE 1 — Storage Integration
   =============================================================================
   Confirms Snowflake can authenticate to AWS and reach the S3 bucket.
   ============================================================================= */

-- Step 1.1 — Inspect the storage integration
USE ROLE ACCOUNTADMIN;
DESC INTEGRATION CUST360_S3_STORAGE_INTEGRATION;

-- Expected properties:
--   ENABLED                   = true
--   STORAGE_ALLOWED_LOCATIONS contains 's3://cust360-northbridge-raw-data-devl-us-east-1/...'
--   STORAGE_AWS_ROLE_ARN      matches the IAM role ARN in input-jsons/aws/config.json
--   STORAGE_AWS_IAM_USER_ARN  matches trust.snowflake_principal_arn
--   STORAGE_AWS_EXTERNAL_ID   matches trust.snowflake_external_id
--
-- If STORAGE_AWS_IAM_USER_ARN / STORAGE_AWS_EXTERNAL_ID don't match the
-- trust block in aws/config.json, Pass 2 of Terraform didn't take effect.
-- Re-run:
--   terraform apply -var-file="terraform.tfvars" -var="enable_trust_policy_update=true"


-- Step 1.2 — Validate connectivity
--
-- Prerequisite: the test file must exist in the bucket path BEFORE running
-- this validation. Upload a placeholder from the CLI first:
--
--   echo "validation probe" > /tmp/validate_all.txt
--   aws s3 cp /tmp/validate_all.txt \
--     s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/validate_all.txt
--
-- If your bucket enforces KMS encryption on upload (via the bucket policy's
-- DenyUnencryptedObjectUploads rule), add:
--   --server-side-encryption aws:kms
--
-- Use 'read' mode — this pipeline is read-only, so 'all' mode will
-- produce false-positive WRITE/DELETE failures (see Troubleshooting).

SELECT SYSTEM$VALIDATE_STORAGE_INTEGRATION(
  'CUST360_S3_STORAGE_INTEGRATION',
  's3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/',
  'validate_all.txt',
  'read'
);

-- Expected: "status": "success" on READ.
-- ('read' mode only tests the READ action. LIST is confirmed in Phase 2.2.)
--
-- Common failures:
--   AccessDenied on LIST  → IAM policy missing s3:ListBucket on bucket ARN
--   AccessDenied on READ  → Trust policy not bootstrapped; re-run Pass 2
--   NoSuchBucket          → Wrong path in STORAGE_ALLOWED_LOCATIONS
--   File not found        → validate_all.txt not uploaded (see prerequisite)


/* =============================================================================
   PHASE 2 — External Stage
   =============================================================================
   Confirms the stage is bound to the integration and can browse S3.
   ============================================================================= */

-- Step 2.1 — Inspect the stage
USE DATABASE CUST360_NORTHBRIDGE_DATABASE;
USE SCHEMA BRONZE;
DESC STAGE RAW_EXTERNAL_STG;

-- Check:
--   STORAGE_INTEGRATION = CUST360_S3_STORAGE_INTEGRATION
--   URL                 points to the bucket path
--   FILE_FORMAT         references JSON_FILE_FORMAT (or equivalent)


-- Step 2.2 — List files through the stage
LIST @CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_EXTERNAL_STG;

-- Expected: at least the validate_all.txt placeholder from Phase 1.2.
-- An error here means the stage is not authorized — go back to Phase 1.


/* =============================================================================
   PHASE 3 — Snowpipe and SQS Wiring
   =============================================================================
   Confirms auto-ingest is configured and S3 events route to Snowpipe.
   ============================================================================= */

-- Step 3.1 — Inspect the pipe
SHOW PIPES IN SCHEMA CUST360_NORTHBRIDGE_DATABASE.BRONZE;

SELECT SYSTEM$PIPE_STATUS('CUST360_NORTHBRIDGE_DATABASE.BRONZE.CUST360_RAW_NORTHBRIDGE_PIPE');

-- Expected fields in the status JSON:
--   "executionState":          "RUNNING"
--   "notificationChannelName": "arn:aws:sqs:..."  ← Snowflake's SQS queue
--
-- Copy the notificationChannelName value — you'll need it for Step 3.2.


-- Step 3.2 — Verify S3 bucket notification wiring (run in a terminal, NOT Snowflake)
--
--   aws s3api get-bucket-notification-configuration \
--     --bucket cust360-northbridge-raw-data-devl-us-east-1
--
-- The output MUST include a QueueConfigurations entry whose QueueArn
-- exactly matches notificationChannelName from Step 3.1.
--
-- If missing, Pass 3 of Terraform didn't complete. Re-run:
--   terraform apply -var-file="terraform.tfvars" -var="enable_snowpipe_creation=true"


/* =============================================================================
   PHASE 4 — Dynamic Table Refresh
   =============================================================================
   Confirms the downstream Dynamic Tables are active and refreshing.
   ============================================================================= */

-- Step 4.1 — Verify dynamic table refresh history
SHOW DYNAMIC TABLES IN SCHEMA CUST360_NORTHBRIDGE_DATABASE.SILVER;

SELECT *
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
  NAME => 'CUST360_NORTHBRIDGE_DATABASE.SILVER.CUST360_CLEAN_NORTHBRIDGE_DT'
))
ORDER BY refresh_start_time DESC
LIMIT 5;

-- Empty history is fine before any data lands.


/* =============================================================================
   PHASE 5 — Smoke Test
   =============================================================================
   One file through the whole pipeline to prove plumbing end-to-end.
   ============================================================================= */

-- Step 5.1 — Upload a single file (run in a terminal):
--   aws s3 cp data/northbridge_sample_3records.json \
--     s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/smoke-test.json
--
-- Step 5.2 — Confirm S3 received it:
--   aws s3 ls s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/smoke-test.json


-- Step 5.3 — Wait 30–60 seconds, then check Snowpipe ingestion
SELECT file_name, status, row_count, row_parsed, first_error_message, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE',
  START_TIME => DATEADD(HOUR, -1, CURRENT_TIMESTAMP)
))
ORDER BY last_load_time DESC;

-- Expected: status = 'Loaded', row_count = 3.
-- If 'Load failed' — see Troubleshooting section at bottom.


-- Step 5.4 — Confirm BRONZE populated
SELECT COUNT(*) AS bronze_row_count
FROM CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;

SELECT ID, INDEX_RECORD_TS, RECORD_COUNT, JSON_VERSION, _STG_FILE_NAME, _COPY_DATA_TS
FROM CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE
ORDER BY _COPY_DATA_TS DESC
LIMIT 3;

-- All NOT NULL columns should have non-null values.



/* =============================================================================
   PHASE 6 — Full Dataset Load
   ============================================================================= */

-- Step 6.1 — (Optional) Clear smoke-test data
TRUNCATE TABLE CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;

-- Corresponding S3 cleanup (run in a terminal):
--   aws s3 rm s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/smoke-test.json


-- Step 6.2 — Upload the full dataset (run in a terminal):
--   aws s3 cp data/ \
--     s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/ \
--     --recursive --include "*.json"


-- Step 6.3 — Monitor ingestion
SELECT file_name, status, row_count, first_error_message, last_load_time
FROM TABLE(INFORMATION_SCHEMA.COPY_HISTORY(
  TABLE_NAME => 'CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE',
  START_TIME => DATEADD(HOUR, -1, CURRENT_TIMESTAMP)
))
ORDER BY last_load_time DESC;


-- Step 6.4 — Verify BRONZE row count
SELECT COUNT(*) AS total_bronze_rows
FROM CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;

-- Expected: 25,000.
-- If short, check COPY_HISTORY for 'Load failed' or 'Partially loaded'.


/* =============================================================================
   PHASE 7 — SILVER Layer
   ============================================================================= */

-- Step 7.1 — Verify SILVER dynamic table populated
SELECT 'CUSTOMERS'            AS tbl, COUNT(*) AS row_count FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.CUSTOMERS
UNION ALL SELECT 'ACCOUNTS',            COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.ACCOUNTS
UNION ALL SELECT 'LOANS',               COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.LOANS
UNION ALL SELECT 'TRANSACTIONS',        COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.TRANSACTIONS;


-- Step 7.3 — Data quality spot-checks

-- 7.3a — No NULLs in business keys
SELECT COUNT(*) AS customers_with_null_id
FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.CUSTOMERS
WHERE customer_id IS NULL;

SELECT COUNT(*) AS transactions_with_null_id
FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.TRANSACTIONS
WHERE transaction_id IS NULL;

-- 7.3b — No duplicates on business keys
SELECT customer_id, COUNT(*) AS dup_count
FROM CUST360_NORTHBRIDGE_DATABASE.SILVER.CUSTOMERS
GROUP BY customer_id
HAVING COUNT(*) > 1;

-- 7.3c — Confirm columns are properly typed (no residual VARIANTs)
DESC TABLE CUST360_NORTHBRIDGE_DATABASE.SILVER.CUSTOMERS;


/* =============================================================================
   PHASE 8 — GOLD Layer
   ============================================================================= */

-- Step 8.1 — Verify dimensions and facts
SELECT 'DIM_CUSTOMER'                AS tbl, COUNT(*) AS row_count FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.DIM_CUSTOMER
UNION ALL SELECT 'DIM_BRANCH',                 COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.DIM_BRANCH
UNION ALL SELECT 'DIM_PRODUCT',                COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.DIM_PRODUCT
UNION ALL SELECT 'DIM_DATE',                   COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.DIM_DATE
UNION ALL SELECT 'FACT_TRANSACTIONS',          COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.FACT_TRANSACTIONS
UNION ALL SELECT 'FACT_LOANS',                 COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.FACT_LOANS
UNION ALL SELECT 'FACT_ACCOUNT_BALANCES',      COUNT(*) FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.FACT_ACCOUNT_BALANCES;

-- Expected: FACT_TRANSACTIONS ≈ 312,000.


-- Step 8.2 — Referential integrity
SELECT COUNT(*) AS orphan_customers
FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.FACT_TRANSACTIONS f
LEFT JOIN CUST360_NORTHBRIDGE_DATABASE.GOLD.DIM_CUSTOMER d
  ON f.customer_key = d.customer_key
WHERE d.customer_key IS NULL;

-- Expected: 0.


-- Step 8.3 — Smoke-test analytical views
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_KPI_SUMMARY        LIMIT 10;
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_SEGMENT_STATS      LIMIT 10;
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_LOAN_PORTFOLIO     LIMIT 10;
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_MONTHLY_TXN_TRENDS LIMIT 10;
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_REGIONAL_PERF      LIMIT 10;
SELECT * FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.V_RISK_DISTRIBUTION  LIMIT 10;


/* =============================================================================
   PHASE 9 — Incremental Load Test
   =============================================================================
   Proves delta loads work, not just the initial dump.
   ============================================================================= */

-- Step 9.1 — Capture baseline counts
SELECT COUNT(*) AS bronze_baseline
FROM CUST360_NORTHBRIDGE_DATABASE.BRONZE.RAW_NORTHBRIDGE;

SELECT COUNT(*) AS fact_baseline
FROM CUST360_NORTHBRIDGE_DATABASE.GOLD.FACT_TRANSACTIONS;


-- Step 9.2 — Upload one additional file (run in a terminal):
--   aws s3 cp data/northbridge_sample_3records.json \
--     s3://cust360-northbridge-raw-data-devl-us-east-1/raw-data/json/delta-$(date +%s).json


-- Step 9.3 — Wait 1–2 minutes, then confirm counts increased
--             Re-run the queries from Step 9.1. BRONZE should be up by
--             the new record count, and GOLD should reflect the
--             downstream propagation after the stream task fires.


/* =============================================================================
   PHASE 10 — Streamlit Dashboard
   =============================================================================

   Deploy via Snowsight → Projects → Streamlit → + Streamlit App using
   STREAMLIT_WH and the STREAMLIT schema.

   Verification checklist (manual):
     [ ] No errors on initial load
     [ ] All 5 tabs render
     [ ] Sidebar filters (Customer Segment, Risk Rating, Region) update charts
     [ ] KPI tab numbers roughly match a direct query of V_KPI_SUMMARY

   ============================================================================= */


/* =============================================================================
   TROUBLESHOOTING REFERENCE
   =============================================================================

   Symptom                                          Likely cause                          Fix
   ------------------------------------------------ ------------------------------------- ------------------------------------
   Validation AccessDenied on LIST                  IAM policy uses bucket/* for          Change to bucket ARN without /*
                                                    ListBucket
   Validation AccessDenied on READ                  Trust policy not bootstrapped         Re-run Pass 2 of Terraform
   S3 upload succeeds but BRONZE empty              SQS notification not wired            Re-run Pass 3; verify with
                                                                                          get-bucket-notification-configuration
   COPY_HISTORY 'Load failed' —                     COPY template doesn't populate        See README 'Debugging NULL
     'NULL result in a non-nullable column'         NOT NULL columns                      non-nullable column' section
   BRONZE populated but SILVER empty                Dynamic table not refreshing          Check scheduling_state is ACTIVE
   SILVER populated but GOLD empty                  Downstream DT not refreshing          ALTER DYNAMIC TABLE ... REFRESH
   Validation fails with PutObject denied           Using 'all' mode instead of 'read'    Use 'read' (read-only pipeline)
   'The specified file was not found' on READ       validate_all.txt not uploaded         See Phase 1.2 prerequisite

   ============================================================================= */


/* =============================================================================
   KEY CONVENTIONS (do not violate)
   =============================================================================
     - All SQL logic lives in .tpl files under infra/platform/tf/templates/ —
       never inline multi-line SQL in HCL.
     - All resource names come from input-jsons/ — never hardcode in .tf files.
     - Read-only pipeline — do not grant s3:PutObject or modify the S3
       bucket policy.
     - debug-outputs.tf must be removed before merging to main.
     - .p8 keypair and terraform.tfvars are gitignored — never commit.
   ============================================================================= */

-- END OF VALIDATION SCRIPT