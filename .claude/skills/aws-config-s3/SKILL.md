---
name: aws-config-s3
description: >
  Use this skill whenever writing, editing, or validating the `aws.s3` block
  inside `input-jsons/aws/config.json` for the Customer 360 / NorthBridge
  Snowflake pipeline. Trigger when the user wants to: set the S3 bucket name,
  region, or KMS key alias; add or modify bucket_keys (folder prefixes);
  enable or disable versioning; add a Terraform state bucket or DynamoDB
  lock table config; understand S3 bucket naming rules; configure the
  raw-data/json prefix for Snowpipe ingestion; or debug a Terraform apply
  failure on aws_s3_bucket or aws_s3_object resources. Also trigger when
  the user asks how to structure the S3 landing zone for the NorthBridge
  JSON files, or wants to add a second bucket for Terraform remote state.
  This skill covers the exact `aws.s3` schema used in the real config —
  not a generic S3 config.
---

# AWS Config — S3 Block

This skill governs the `aws.s3` block in `input-jsons/aws/config.json`.
It is consumed by `module.s3` (Phase 1.1) in `main.tf`.

---

## Current Config Structure (as-is)

```json
{
  "aws": {
    "region": "us-east-1",
    "s3": {
      "bucket_name":  "aws-snowflake-project",
      "bucket_keys":  ["raw-data/csv", "raw-data/json"],
      "versioning":   true,
      "kms_key_alias": "SB-KMS"
    }
  }
}
```

---

## Full JSON Schema

```json
{
  "aws": {
    "region": "<string, required — must match providers-aws.tf>",
    "s3": {
      "bucket_name":   "<string, required — globally unique, lowercase, hyphens only>",
      "bucket_keys":   ["<prefix1>", "<prefix2>"],
      "versioning":    "<bool, default false>",
      "kms_key_alias": "<string — alias of the KMS key for server-side encryption>",
      "force_destroy": "<bool, default false — never true in production>",
      "lifecycle_rules": [
        {
          "id":              "<string — unique rule identifier>",
          "enabled":         "<bool>",
          "prefix":          "<S3 key prefix this rule applies to>",
          "expiration_days": "<number — delete objects after N days>"
        }
      ]
    },
    "tf_state": {
      "bucket_name":    "<string — separate bucket for Terraform remote state>",
      "dynamodb_table": "<string — DynamoDB table name for state locking>",
      "kms_key_alias":  "<string — KMS alias for state bucket encryption>"
    }
  }
}
```

---

## Field Reference

### `aws` (top-level)

| Field | Required | Notes |
|---|---|---|
| `region` | ✅ | Must match the region in `providers-aws.tf` and the Snowflake storage integration allowed location |

### `aws.s3`

| Field | Required | Notes |
|---|---|---|
| `bucket_name` | ✅ | Globally unique; 3–63 chars; lowercase letters, numbers, hyphens only |
| `bucket_keys` | ✅ | List of S3 "folder" prefixes to initialise; must include `raw-data/json` for Snowpipe |
| `versioning` | ❌ | Default `false`; set `true` in production to enable object recovery |
| `kms_key_alias` | ❌ | Alias of an existing AWS KMS key (e.g. `SB-KMS`); omit to use SSE-S3 instead |
| `force_destroy` | ❌ | Default `false`; **never `true` in production** — destroys all objects on `terraform destroy` |
| `lifecycle_rules` | ❌ | Add to control storage costs; recommended for raw JSON files |

### `aws.tf_state` (add if not present)

| Field | Required | Notes |
|---|---|---|
| `bucket_name` | ✅ | Must differ from the data bucket; e.g. `northbridge-tf-state` |
| `dynamodb_table` | ✅ | Used for Terraform state locking; e.g. `northbridge-tf-lock` |
| `kms_key_alias` | ❌ | Recommended to encrypt state at rest |

---

## NorthBridge Target Config

```json
{
  "aws": {
    "region": "us-east-1",
    "s3": {
      "bucket_name":   "northbridge-raw-data",
      "bucket_keys":   [
        "raw-data/json"
      ],
      "versioning":    true,
      "kms_key_alias": "SB-KMS",
      "force_destroy": false,
      "lifecycle_rules": [
        {
          "id":              "expire-raw-json-90-days",
          "enabled":         true,
          "prefix":          "raw-data/json",
          "expiration_days": 90
        }
      ]
    },
    "tf_state": {
      "bucket_name":    "northbridge-tf-state",
      "dynamodb_table": "northbridge-tf-lock",
      "kms_key_alias":  "SB-KMS"
    }
  }
}
```

### What changed from the original config

| Field | Original | NorthBridge target | Reason |
|---|---|---|---|
| `bucket_name` | `aws-snowflake-project` | `northbridge-raw-data` | Descriptive, project-scoped name |
| `bucket_keys` | `["raw-data/csv", "raw-data/json"]` | `["raw-data/json"]` | NorthBridge uses JSON only; remove unused CSV prefix |
| `tf_state` block | Missing | Added | Required for S3 remote backend + DynamoDB lock |
| `lifecycle_rules` | Missing | Added | Controls storage cost on raw ingestion files |

---

## S3 Bucket Naming Rules

- 3–63 characters
- Lowercase letters, numbers, hyphens only
- Cannot start or end with a hyphen
- Cannot be formatted as an IP address (e.g. `192.168.1.1`)
- Must be globally unique across all AWS accounts and regions

---

## KMS Key Usage

When `kms_key_alias` is set, Terraform looks up the KMS key ARN by alias and
applies SSE-KMS encryption to all objects written to the bucket. The IAM role
for Snowflake (`aws.iam.role_name`) must have `kms:Decrypt` and
`kms:GenerateDataKey*` permissions on this key — these are already defined
in the `SnowflakeKMSAccessPolicy` in `aws.iam.policies`.

If the KMS key alias does not exist in the target AWS account, `terraform plan`
will fail with `NotFoundException`. Create the key first or remove
`kms_key_alias` to fall back to SSE-S3.

---

## Common Mistakes

- **Keeping the CSV prefix when the pipeline is JSON-only** — `raw-data/csv` creates a dead prefix and adds noise to S3 listings; remove it.
- **`bucket_name` containing uppercase letters** — causes an immediate `InvalidBucketName` API error.
- **Missing `raw-data/json` in `bucket_keys`** — Snowpipe's external stage URL (`s3://bucket/raw-data/json/`) must exist as a prefix; without the key, Snowflake `LIST @stage` returns empty.
- **Region mismatch between `aws.region` and `providers-aws.tf`** — causes `BucketRegionError` on every Snowflake stage operation.
- **Omitting `tf_state` block** — without a remote state bucket and DynamoDB lock table, the Terraform backend in `backend.tf` cannot be initialised.