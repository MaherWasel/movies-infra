#!/bin/bash
set -e

# Config via environment variables (Factor 3)
PROJECT="${GCP_PROJECT_ID:?Set GCP_PROJECT_ID environment variable}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Movies App — Full Destroy ==="
echo "Project: $PROJECT"
echo ""

# 1. Destroy infrastructure
echo "--- Destroying infrastructure..."
cd "$ROOT_DIR"
terraform destroy -auto-approve 2>/dev/null || true

# 2. Delete state bucket
echo "--- Deleting state bucket..."
gsutil rm -r gs://movies-infra-tfstate 2>/dev/null || true

# 3. Delete Firestore
echo "--- Deleting Firestore..."
gcloud firestore databases delete --database="(default)" --project=$PROJECT --quiet 2>/dev/null || true

# 4. Delete local repos
echo "--- Deleting local repos..."
cd "$ROOT_DIR/.."
rm -rf movies-movie-service movies-review-service movies-infra movies-frontend

echo ""
echo "=== Destroy Complete — everything is gone ==="
