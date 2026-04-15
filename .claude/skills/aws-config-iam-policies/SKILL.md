---
name: aws-config-iam-policies
description: >
  Use this skill whenever writing, editing, or validating the `aws.iam` block
  inside `infra/platform/tf/config/aws/config.json` for the Customer 360 / NorthBridge
  Snowflake pipeline. Trigger when the user wants to: add or modify the IAM
  role name; add, remove, or update IAM policy statements in the `policies[]`
  array; adjust S3 or KMS permissions for the Snowflake storage integration
  role; add a new policy for SQS (required for Snowpipe auto-ingest); set the
  `effect`, `action`, `resource`, or `sid` on any policy; understand which
  IAM permissions are required for each Snowpipe and storage integration
  feature; or debug an AWS AccessDenied error from Snowflake when reading
  from S3 or using KMS. Also trigger when the user asks what IAM permissions
  Snowflake needs, or wants to tighten the policy to least-privilege.
---

# AWS Config — IAM Role & Policies Block

This skill governs the `aws.iam` block in `infra/platform/tf/config/aws/config.json`.
It is consumed by `module.iam_role` (Phase 1.2) and
`module.aws_iam_role_final` (Phase 3) in `main.tf`.

---

## Current Config Structure (as-is)

```json
{
  "aws": {
    "iam": {
      "role_name": "snowflake-external-stage-role",
      "policies": [
        {
          "name":     "SnowflakeS3ListBucketPolicy",
          "action":   ["s3:ListBucket", "s3:GetBucketLocation"],
          "effect":   "Allow",
          "resource": "s3-bucket-arn",
          "sid":      "SnowflakeS3ListBucket"
        },
        {
          "name":     "SnowflakeS3ObjectAccessPolicy",
          "action":   ["s3:GetObject", "s3:GetObjectVersion", "s3:PutObject", "s3:DeleteObject"],
          "effect":   "Allow",
          "resource": "s3-bucket-arn/*",
          "sid":      "SnowflakeS3ObjectAccess"
        },
        {
          "name":     "SnowflakeKMSAccessPolicy",
          "action":   ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"],
          "effect":   "Allow",
          "resource": "kms-key-arn",
          "sid":      "SnowflakeKMSAccess"
        }
      ]
    }
  }
}
```

---

## Full JSON Schema

```json
{
  "aws": {
    "iam": {
      "role_name": "<string, required — AWS IAM role name>",
      "policies": [
        {
          "name":     "<string, required — logical policy name; used as Terraform resource key>",
          "sid":      "<string, required — Statement ID; alphanumeric, no spaces>",
          "effect":   "<Allow | Deny, required>",
          "action":   ["<IAM action string>"],
          "resource": "<ARN or token string resolved by locals.tf — see Resource Tokens>",
          "condition": {
            "<condition_operator>": {
              "<condition_key>": "<condition_value>"
            }
          }
        }
      ]
    }
  }
}
```

---

## Resource Token Reference

The `resource` field uses **token strings** that `locals.tf` resolves to real
ARNs at plan time. Never paste raw ARNs directly — use the tokens.

| Token | Resolves to | Use for |
|---|---|---|
| `s3-bucket-arn` | `arn:aws:s3:::${bucket_name}` | Bucket-level actions (ListBucket, GetBucketLocation) |
| `s3-bucket-arn/*` | `arn:aws:s3:::${bucket_name}/*` | Object-level actions (GetObject, PutObject) |
| `kms-key-arn` | ARN of the KMS key matching `aws.s3.kms_key_alias` | KMS encryption/decryption actions |
| `sqs-queue-arn` | ARN of the SQS queue created by Snowpipe | SQS SendMessage (required for auto-ingest) |

---

## Required Permissions by Feature

### Snowflake storage integration (always required)

| Policy | Actions | Resource token |
|---|---|---|
| `SnowflakeS3ListBucketPolicy` | `s3:ListBucket`, `s3:GetBucketLocation` | `s3-bucket-arn` |
| `SnowflakeS3ObjectAccessPolicy` | `s3:GetObject`, `s3:GetObjectVersion` | `s3-bucket-arn/*` |

### KMS-encrypted bucket (required when `aws.s3.kms_key_alias` is set)

| Policy | Actions | Resource token |
|---|---|---|
| `SnowflakeKMSAccessPolicy` | `kms:Decrypt`, `kms:GenerateDataKey*`, `kms:DescribeKey` | `kms-key-arn` |

### Snowpipe auto-ingest (add when `enable_snowpipe_creation=true`)

| Policy | Actions | Resource token |
|---|---|---|
| `SnowflakeSQSSendMessagePolicy` | `sqs:SendMessage`, `sqs:GetQueueUrl`, `sqs:GetQueueAttributes` | `sqs-queue-arn` |

> `s3:PutObject` and `s3:DeleteObject` in the original config grant Snowflake
> write access to the bucket. For a read-only ingestion pipeline these should
> be removed to follow least-privilege. Keep them only if Snowflake needs to
> write back results (e.g. unload operations).

---

## NorthBridge Target Config

```json
{
  "aws": {
    "iam": {
      "role_name": "northbridge-snowflake-role",
      "policies": [
        {
          "name":     "SnowflakeS3ListBucketPolicy",
          "sid":      "SnowflakeS3ListBucket",
          "effect":   "Allow",
          "action":   ["s3:ListBucket", "s3:GetBucketLocation"],
          "resource": "s3-bucket-arn"
        },
        {
          "name":     "SnowflakeS3ObjectAccessPolicy",
          "sid":      "SnowflakeS3ObjectAccess",
          "effect":   "Allow",
          "action":   ["s3:GetObject", "s3:GetObjectVersion"],
          "resource": "s3-bucket-arn/*"
        },
        {
          "name":     "SnowflakeKMSAccessPolicy",
          "sid":      "SnowflakeKMSAccess",
          "effect":   "Allow",
          "action":   ["kms:Decrypt", "kms:GenerateDataKey*", "kms:DescribeKey"],
          "resource": "kms-key-arn"
        },
        {
          "name":     "SnowflakeSQSSendMessagePolicy",
          "sid":      "SnowflakeSQSSendMessage",
          "effect":   "Allow",
          "action":   ["sqs:SendMessage", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"],
          "resource": "sqs-queue-arn"
        }
      ]
    }
  }
}
```

### What changed from the original config

| Change | Original | NorthBridge target | Reason |
|---|---|---|---|
| `role_name` | `snowflake-external-stage-role` | `northbridge-snowflake-role` | Project-scoped name |
| `s3:PutObject`, `s3:DeleteObject` | Present | Removed | Least-privilege — ingestion is read-only |
| `kms:Encrypt`, `kms:ReEncrypt*` | Present | Removed | Snowflake only needs to decrypt; not encrypt |
| SQS policy | Missing | Added | Required for Snowpipe `auto_ingest: true` |

---

## IAM Policy Authoring Rules

- **`sid` must be alphanumeric** — no spaces, hyphens, or underscores in the `sid` value; Terraform will produce an `InvalidSid` error.
- **One resource per policy statement** — split bucket-level and object-level actions into separate policy objects; they require different resource ARNs.
- **Use tokens, not raw ARNs** — `locals.tf` resolves tokens at plan time using the bucket name and KMS alias from the config; hardcoded ARNs break environment portability.
- **`name` is the Terraform map key** — it must be unique across all entries in `policies[]`; duplicates cause a Terraform `for_each` collision error.

---

## Common Mistakes

- **Using `s3-bucket-arn/*` for `s3:ListBucket`** — `ListBucket` requires the bucket ARN without the `/*` wildcard; using `/*` causes `AccessDenied` on LIST operations.
- **Missing SQS policy when `auto_ingest: true`** — Snowpipe sends S3 event notifications via SQS; without `sqs:SendMessage` the pipe silently fails to auto-ingest.
- **Keeping `s3:PutObject` and `s3:DeleteObject` for read-only ingestion** — violates least-privilege; remove them unless Snowflake unload or data export is required.
- **`kms:Encrypt` on a read-only role** — Snowflake only needs `kms:Decrypt` and `kms:GenerateDataKey*` to read KMS-encrypted S3 objects; `kms:Encrypt` and `kms:ReEncrypt*` are unnecessary.
- **`sid` with spaces or hyphens** — `"sid": "Snowflake S3 Access"` will fail; use `"SnowflakeS3Access"` (CamelCase, no separators).