# AWS Retail Lakehouse Project

## Overview

This repository contains an AWS retail lakehouse implementation that ingests
purchase, weather, and review data into S3, transforms it through Bronze,
Silver, and Gold layers, and exposes analytical tables through Athena and
Amazon Redshift Spectrum.

This document describes the code and the latest recorded project notes. It is
not a live check of AWS resources. Runtime status, deployed script versions,
and costs should be verified in the target AWS account before relying on them.

## Architecture

```text
PostgreSQL ── DMS CDC ─────────┐
Weather API ─ Lambda ──────────┼──> S3 Bronze
Reviews source ─ Lambda ───────┘       │
                                       ▼
                              AWS Glue ETL jobs
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

Terraform configuration for the AWS resources is in
[`infrastructure/terraform`](../infrastructure/terraform/). Glue job scripts
are in [`processing/glue_jobs`](../processing/glue_jobs/), and the DQ ruleset
is in [`quality`](../quality/).

## Data flow

### Bronze: ingestion

- AWS DMS captures PostgreSQL purchase changes and writes them to S3.
- A weather Lambda writes API observations to S3 on an hourly schedule.
- A reviews Lambda writes review records to S3 on a scheduled basis.
- Glue Data Catalog databases describe the Bronze, Silver, and Gold layers.

Project notes record successful tests for all three ingestion paths. These
results are historical and are not a live check of deployed AWS resources.

### Silver: cleaned tables

The Glue jobs in `processing/glue_jobs/` normalize the source data and write
Iceberg tables for purchases, weather, and reviews. The purchases job merges
incoming records by `purchase_id`, using the DMS timestamp to select updates.

The purchases job also contains a Glue Data Quality evaluation. It reads the
DQDL ruleset from the scripts S3 bucket and checks the resulting
`ruleOutcomes`; a failed rule causes the job to fail. The first recorded run
using the S3 URI as the `ruleset` value failed because Glue parsed the URI as
DQDL. The code was subsequently changed to fetch the ruleset contents from S3.
On 2026-11-03, the updated script was uploaded and the Glue job run
`jr_975aab682ed863901bed9ca33b2ce62c58795c09bd909cfc0051f7e0b14d52cc`
reported `SUCCEEDED`. This verifies the job completed with the DQ gate enabled;
consult the Glue run logs or published DQ results for the per-rule outcome
details.

### Gold: correlated data

`gold_weather_sales.py` joins purchases with customer region, hourly weather,
and daily product review aggregates. It writes the `gold_weather_sales`
Iceberg table, which is queried through Athena and Redshift Spectrum.

The latest project notes record 43 Gold rows and matching query results in
Athena and Redshift. They also report that the available source dates did not
overlap: purchases were from October, while weather and reviews were collected
in November. As a result, weather and review aggregates were null for the
purchase dates, and the weather grouping was dry. This is a data coverage
limitation, not evidence that the correlation is meaningful.

## Infrastructure and security configuration

The Terraform configuration includes S3 buckets for Bronze, Silver, Gold,
scripts, logs, and quarantine; KMS encryption; S3 public-access blocks and
versioning; IAM roles and policies; Glue jobs; and other resources used by the
pipeline.

Do not treat the repository as proof that every AWS resource is currently
deployed or healthy. In particular:

- The recorded Redshift and pipeline verification is historical.
- Lake Formation tag-based access control, monitoring, and CI/CD were listed
  as follow-up work in the project notes. Verify their implementation in
  Terraform and workflows before describing them as deployed.
- The project notes contain environment details that should not be copied
  into public documentation. Use `env.sh` and AWS-managed secret stores for
  operational configuration; never publish credentials.

## Known limitations and next steps

1. **Inspect DQ details as needed.** The updated Glue job completed
   successfully on 2026-11-03. Check its run logs and published DQ results for
   per-rule metrics and retain the run ID when recording operational evidence.
2. **Build aligned history.** Accumulate or backfill overlapping purchase,
   weather, and review dates before interpreting Gold correlations.
3. **Confirm optional operational features.** Review Lake Formation
   enforcement, alerting/monitoring, CI/CD, and cost tuning independently;
   they are not established by the historical pipeline query results.
4. **Review resources before teardown.** `terraform destroy` is destructive.
   Confirm the account, Terraform workspace/state, data-retention needs, and
   S3 object/version state before applying it. KMS key deletion is scheduled,
   and retained encrypted data may become unreadable if its key is deleted.

## Operational references

- [Terraform configuration](../infrastructure/terraform/)
- [Glue ETL scripts](../processing/glue_jobs/)
- [DQ rules](../quality/)
