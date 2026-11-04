# AWS Retail Lakehouse

An AWS data-lakehouse project that ingests retail purchases, weather observations, and product reviews; transforms them into Apache Iceberg tables; and makes the results queryable with Athena and Amazon Redshift Spectrum.

> **Before sharing this repository:** credentials were previously committed in its Git history. Rotating them and cleaning the history are still required before publishing; see the security note at the end.

## Architecture

```text
PostgreSQL ── AWS DMS CDC ─────┐
Weather API ─ scheduled Lambda ├──> S3 Bronze
Reviews source ─ Lambda ───────┘       │
                                       ▼
                              AWS Glue ETL (PySpark)
                                       │
                         ┌─────────────┴─────────────┐
                         ▼                           ▼
                 S3 Silver (Iceberg)          S3 Gold (Iceberg)
                 purchases, weather,          weather-sales
                 reviews                           │
                                      ┌────────────┴───────────┐
                                      ▼                        ▼
                                   Athena            Redshift Spectrum
```

The Bronze layer stores ingested data in S3. Glue jobs clean and transform it into Silver Iceberg tables, then join the data into a Gold weather-and-sales table. Glue Data Quality rules are defined for purchases.

## Repository layout

| Path | Contents |
| --- | --- |
| `infrastructure/terraform/` | Terraform configuration for AWS resources, including S3, IAM, DMS, Lambda, Glue, RDS, and Redshift |
| `infrastructure/bucket.sh` | Creates and configures the S3 bucket used for Terraform remote state |
| `ingestion/` | DMS configuration and Lambda ingestion code for weather and reviews |
| `processing/glue_jobs/` | Silver and Gold Glue PySpark jobs |
| `quality/` | Glue Data Quality rules |
| `docs/project-overview.md` | More detail on the architecture, data flow, and known limitations |

## Prerequisites

- An AWS account and AWS CLI credentials for the target account
- Terraform 1.6 or later
- A VPC and at least two private subnets in different Availability Zones for RDS and DMS
- Bash (Linux or WSL) to run `infrastructure/bucket.sh`

The AWS resources can incur charges, including RDS, DMS, Glue, and Redshift Serverless. Review the Terraform plan and expected costs before applying it.

## Configure and deploy

1. Review the Terraform variables and resource definitions in `infrastructure/terraform/`. Supply the required values for your own AWS environment, including the project/environment names, network IDs, PostgreSQL endpoint, and DMS password. Keep secret values in an appropriate secrets manager or an untracked local variable file.
2. Copy `env.example` to the ignored local `env.sh`, replace its placeholders, and source it. Copy `infrastructure/terraform/terraform.tfvars.example` to the ignored local `infrastructure/terraform/terraform.tfvars`, then replace its placeholders:

   ```bash
   cp -n env.example env.sh
   # Edit env.sh with your account ID, then:
   source ./env.sh
   cp -n infrastructure/terraform/terraform.tfvars.example \
     infrastructure/terraform/terraform.tfvars
   ```

   Supply the sensitive `dms_password`, `rds_master_password`, and
   `redshift_admin_password` through Terraform prompts or `TF_VAR_*`
   environment variables. Terraform state contains sensitive values; protect
   the remote state bucket and restrict access to it.

3. Configure the environment variables needed by the remote-state bucket script, then create the bucket:

   ```bash
   export PROJECT="retail-lakehouse"
   export ENV="dev"
   export REGION="us-east-1"
   export ACCOUNT_ID="<your-aws-account-id>"
   ./infrastructure/bucket.sh
   ```

4. Initialize Terraform with that bucket as the backend, then review and apply the configuration:

   ```bash
   cd infrastructure/terraform
   terraform init \
     -backend-config="bucket=${PROJECT}-tfstate-${ACCOUNT_ID}" \
     -backend-config="key=${ENV}/lakehouse.tfstate" \
     -backend-config="region=${REGION}"
   terraform validate
   terraform plan
   # Apply only after reviewing the plan and confirming the target account:
   terraform apply
   ```

Terraform may prompt for required variables if they are not supplied through a local variable file or another supported mechanism. Do not commit credentials, state files, or saved plans. `terraform destroy` is destructive and can delete data or infrastructure; confirm the target account and retention requirements before using it.

## Data flow

1. DMS captures PostgreSQL changes; the weather and reviews Lambda functions write source data to S3 Bronze.
2. Run the Silver Glue jobs to clean and write the purchases, weather, and reviews Iceberg tables.
3. Run the Gold Glue job to join the Silver data into the weather-and-sales table.
4. Query the cataloged tables with Athena or Redshift Spectrum.

The Glue jobs are configured in Terraform. Check the deployed job arguments and S3 paths in your AWS environment before running them.

## Project status and limitations

The project notes report that the ingestion, Silver/Gold transformations, Athena queries, and Redshift Spectrum queries were verified in November 2026. These are historical results, not a live check of AWS resources. The recorded data did not cover matching purchase, weather, and review dates, so weather and review fields in the Gold results were null or defaulted. Accumulate or backfill aligned data before interpreting the correlations.

See [`docs/project-overview.md`](docs/project-overview.md) for additional context and caveats.

## Before publishing

The previous Git history contains credentials and a large Terraform provider
binary. The current working tree excludes sensitive local files, but that does
not remove their historical versions. Rotate any credentials that were ever
committed, then rewrite the repository history before pushing it to a public
GitHub repository. History rewriting changes commit IDs and requires a
force-push; coordinate with collaborators and ensure you have a backup first.