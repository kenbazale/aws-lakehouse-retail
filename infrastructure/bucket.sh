#!/usr/bin/env bash
set -euo pipefail

: "${PROJECT:?Set PROJECT, e.g. export PROJECT=retail-lakehouse}"
: "${ACCOUNT_ID:?Set ACCOUNT_ID to the AWS account ID}"
: "${REGION:?Set REGION, e.g. export REGION=us-east-1}"

BUCKET="${PROJECT}-tfstate-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "${BUCKET}" 2>/dev/null; then
  echo "State bucket ${BUCKET} already exists"
else
  if [[ "${REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET}" --region "${REGION}"
  else
    aws s3api create-bucket \
      --bucket "${BUCKET}" \
      --region "${REGION}" \
      --create-bucket-configuration LocationConstraint="${REGION}"
  fi
  echo "Created state bucket ${BUCKET}"
fi

aws s3api put-bucket-versioning \
  --bucket "${BUCKET}" \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption \
  --bucket "${BUCKET}" \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws s3api put-public-access-block \
  --bucket "${BUCKET}" \
  --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "Remote state bucket ${BUCKET} is ready. Initialize with:"
echo "  terraform init \\"
echo "    -backend-config=\"bucket=${BUCKET}\" \\"
echo "    -backend-config=\"key=\${ENV}/lakehouse.tfstate\" \\"
echo "    -backend-config=\"region=${REGION}\""
