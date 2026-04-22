# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Bug Fixes

- Update template paths in config.json and add validation for template filenames
- Add table grant pairs and resource for Snowflake privileges workaround

### Documentation

- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]

### Features

- Add deploy workflow for Streamlit app and update Terraform workflows
- Add Streamlit app deployment step and create dashboard script

### Refactor

- Rename CTE and simplify query structure in clean_northbridge.tpl

## [Rel-013-20260420205108] - 2026-04-20

### Documentation

- Update CHANGELOG.md [skip ci]

### Features

- Add dynamic table name lookup for Snowflake objects in locals.tf

## [Rel-012-20260420201549] - 2026-04-20

### Documentation

- Update CHANGELOG.md [skip ci]

### Features

- Update dynamic table configurations for GOLD layer and adjust permissions in README

## [Rel-011-20260420192143] - 2026-04-20

### Documentation

- Update CHANGELOG.md [skip ci]

### Features

- Add dynamic tables for Gold layer and update comments in existing templates
- Update README and config files for Gold layer dynamic tables
- Update dynamic table templates to use consistent variable naming for source table

## [Rel-010-20260420180516] - 2026-04-20

### Bug Fixes

- Update Snowpipe copy template and adjust compression settings

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-009-20260420152720] - 2026-04-20

### Bug Fixes

- Improve timestamp parsing for extract_date in NorthBridge copy statements

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-008-20260420150142] - 2026-04-20

### Bug Fixes

- Correct timestamp parsing for extract_date in NorthBridge copy statements

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-007-20260420135105] - 2026-04-20

### Bug Fixes

- Update nullable fields and comments in NorthBridge schema and copy statements

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-006-20260417135118] - 2026-04-17

### Documentation

- Update CHANGELOG.md [skip ci]

### Features

- Add source schema and table for NorthBridge dataset in config files

## [Rel-005-20260417015954] - 2026-04-17

### Bug Fixes

- Update Snowpipe grants and enhance IAM trust policy description

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-004-20260417011644] - 2026-04-17

### Bug Fixes

- Update IAM resource permissions and correct S3 stage URL in configuration

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-003-20260417005401] - 2026-04-17

### Bug Fixes

- Remove LastModified timestamp from locals.tf

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-002-20260416203436] - 2026-04-16

### Bug Fixes

- Update cloud provider from snowflake to platform in deploy workflows and adjust working directory in env.json
- Update onboarding workflow reference to specific feature branch
- Format JSON structure in env.json for consistency
- Remove unused GitHub configuration from env.json
- Update CODEOWNERS and adjust Terraform workflows for AWS and Snowflake configurations
- Update expiration_days for lifecycle rule to 90 days in config.json
- Update organization name in backend.tf for Snowflake projects and enhance README with key encoding instructions
- Correct indentation and formatting in backend.tf for Terraform configuration
- Update Terraform workflows to use Snowflake organization token and adjust expiration_days to 91 in config.json
- Remove unnecessary whitespace in backend.tf for Terraform configuration
- Update CI workflow to use specific version of reusable workflow for backend type remote

### Documentation

- Update CHANGELOG.md [skip ci]

## [Rel-001-20260415171708] - 2026-04-15

### Bug Fixes

- Adjust formatting in README.md for clarity
- Disable versioning in S3 bucket configuration
- Correct formatting in environment validation condition
- Update Terraform backend configuration for organization and workspace name
- Restore Snowflake provider variables for HCP Terraform compatibility
- Pass Snowflake private key as Terraform variable
- Strip PEM headers from base64-decoded private key for Snowflake JWT auth
- Pass full PEM content to Snowflake provider without stripping headers
- Pass raw private key body directly without base64 encoding
- Reconstruct PEM format from raw key body for Snowflake provider
- Align formatting of variable assignments in Terraform configuration files
- Add 64-char line wrapping to reconstructed PEM private key
- Use SNOWFLAKE_PRIVATE_KEY env var instead of Terraform variable
- Remove unused snowflake_private_key variable and update README
- Revert to Terraform variable with PEM reconstruction for private key
- Trimspace private key variable to strip trailing whitespace
- Use base64-encoded full PEM file for private key
- Strip whitespace from private key before base64 decoding
- Change authenticator from SNOWFLAKE_JWT to JWT
- Remove explicit authenticator, let provider auto-detect from private_key
- Restore authenticator = SNOWFLAKE_JWT to prevent password auth fallback
- Update CI workflow reference to use main branch

### Documentation

- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update HCP variable set instructions with working configuration
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]
- Update CHANGELOG.md [skip ci]

### Features

- Add Terraform modules and configuration for AWS-Snowflake integration
- Add Terraform configuration for AWS resources and Snowflake integration
- Update CI workflow to include push triggers and add setup project workflow
- Update CI workflows and remove obsolete onboarding files
- Update CI workflow to correct cloud provider configuration and ensure proper path monitoring
- Update S3 module source and comment out IAM role module in main.tf
- Comment out Snowflake configuration and IAM role settings in locals.tf
- Comment out unused KMS key data source and Snowflake config path in variables.tf
- Update S3 module source reference to a specific commit hash
- Update S3 module source reference to use a specific version
- Refactor locals.tf for improved readability and reformat IAM role configuration
- Refactor Terraform modules in main.tf and update variable definitions in variables.tf
- Add new AWS configuration files and update bucket name in existing configs
- Update S3 module source references to use Git URLs and correct bucket name in config
- Update module source references to specific versions in main.tf
- Remove unused AWS region data source from locals.tf
- Update Terraform variable file path to use development environment
- Configure NorthBridge Customer 360 pipeline AWS and Snowflake resources
- Update Snowpipe copy template references and improve README formatting
- Comment out bug branch trigger in CI workflow
- Re-enable bug branch trigger in CI workflow
- Add security-events permission to CI workflow
- Enable downloading of external modules in checkov hook
- Update project code to cust360sf in Terraform variables
- Update AWS and Snowflake config paths for development environment
- Update project code to cust360sf and change default environment to ci
- Uncomment Snowflake organization and account name variables in variables.tf
- Add Snowflake configuration files for dev, prod, and test environments
- Update Snowflake authentication process with RSA keypair and base64 encoding
- Enhance README and Terraform configurations with provisioner roles and tagging metadata
- Add new variables for project configuration and update resource timestamps
- Update Terraform variable files with additional project metadata and configuration
- Implemen phase 1,  2 and 3
- Implement Snowpipes and Dynamic Tables outputs in Phase 4 and 5

### Miscellaneous Tasks

- Remove AWS configuration JSON file
- Remove pre-commit configuration file

### Refactor

- Comment out unused Snowflake organization and account name variables
- Remove checkov hook from pre-commit configuration

### Debug

- Add temporary outputs to verify private key integrity in HCP

<!-- generated by git-cliff -->
