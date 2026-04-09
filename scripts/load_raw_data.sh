#!/bin/bash
###############################################################################
# Upload large raw data files to GCS and load into BigQuery landing dataset.
#
# Run once after bootstrap to populate the landing layer with data too large
# for dbt seeds (transactions_data.csv ~1.2GB, train_fraud_labels ~152MB).
#
# Prerequisites:
#   - gcloud auth application-default login
#   - Bootstrap Terraform applied (GCS bucket + BigQuery datasets exist)
#
# Usage:
#   ./scripts/load_raw_data.sh
###############################################################################

set -euo pipefail

PROJECT_ID="${GCP_PROJECT_ID:-mpc-caixabank-ai}"
BUCKET="gs://${PROJECT_ID}-raw-data"
DATASET="landing"
REGION="europe-southwest1"

# Copy small CSVs to dbt seeds (if not already there)
echo "=== Copying seed files ==="
if [ ! -f dbt/seeds/users_data.csv ] && [ -f data/raw/users_data.csv ]; then
    cp data/raw/users_data.csv dbt/seeds/users_data.csv
    echo "Copied users_data.csv to dbt/seeds/"
fi
if [ ! -f dbt/seeds/cards_data.csv ] && [ -f data/raw/cards_data.csv ]; then
    cp data/raw/cards_data.csv dbt/seeds/cards_data.csv
    echo "Copied cards_data.csv to dbt/seeds/"
fi

echo ""
echo "=== Uploading raw data to GCS bucket: ${BUCKET} ==="

# Upload transactions CSV (~1.2GB)
echo "Uploading transactions_data.csv..."
gsutil -o GSUtil:parallel_composite_upload_threshold=150M \
    cp data/raw/transactions_data.csv "${BUCKET}/transactions_data.csv"

# Prepare and upload fraud labels (JSON dict → CSV)
echo "Preparing fraud labels..."
python scripts/prepare_labels.py

echo "Uploading train_fraud_labels.csv..."
gsutil cp data/processed/train_fraud_labels.csv "${BUCKET}/train_fraud_labels.csv"

echo ""
echo "=== Loading data into BigQuery dataset: ${PROJECT_ID}:${DATASET} ==="

# Load transactions into BigQuery
echo "Loading transactions_data..."
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --allow_quoted_newlines \
    --replace \
    --location="${REGION}" \
    "${PROJECT_ID}:${DATASET}.transactions_data" \
    "${BUCKET}/transactions_data.csv"

# Load fraud labels into BigQuery
echo "Loading train_fraud_labels..."
bq load \
    --source_format=CSV \
    --skip_leading_rows=1 \
    --replace \
    --location="${REGION}" \
    "${PROJECT_ID}:${DATASET}.train_fraud_labels" \
    "${BUCKET}/train_fraud_labels.csv" \
    "transaction_id:STRING,is_fraud:STRING"

echo ""
echo "=== Done! Verify with: ==="
echo "  bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.transactions_data\`'"
echo "  bq query --use_legacy_sql=false 'SELECT COUNT(*) FROM \`${PROJECT_ID}.${DATASET}.train_fraud_labels\`'"
