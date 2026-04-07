#!/bin/bash
set -e

PROJECT="project-e005e972-f26f-4d68-b51"
REGION="me-central1"
REGISTRY="$REGION-docker.pkg.dev/$PROJECT/movies-docker"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Movies App — Full Deploy ==="
echo "Project: $PROJECT"
echo ""

# 1. State bucket
echo "--- Creating state bucket (if needed)..."
gsutil mb -l $REGION gs://movies-infra-tfstate 2>/dev/null || true

# 2. Terraform init + Artifact Registry first
echo "--- Initializing Terraform..."
cd "$ROOT_DIR"
cat > terraform.tfvars << EOF
project_id           = "$PROJECT"
region               = "$REGION"
github_owner         = "MaherWasel"
firebase_project_id  = "$PROJECT"
redis_tier           = "BASIC"
redis_memory_size_gb = 1
EOF

terraform init -input=false
terraform apply -target=module.apis -target=module.artifact_registry -auto-approve

# 3. Build & push images
echo "--- Building Docker images..."
cd "$ROOT_DIR/../movies-movie-service"
gcloud builds submit --tag $REGISTRY/movie-service:latest --region=$REGION --project=$PROJECT --quiet

cd "$ROOT_DIR/../movies-review-service"
gcloud builds submit --tag $REGISTRY/review-service:latest --region=$REGION --project=$PROJECT --quiet
gcloud builds submit --config=cloudbuild-worker.yaml --region=$REGION --project=$PROJECT --quiet

# 4. Deploy everything
echo "--- Deploying infrastructure..."
cd "$ROOT_DIR"
terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)" 2>/dev/null || true
terraform apply -auto-approve

# 5. Seed data
echo "--- Seeding movies..."
gcloud run jobs execute seed-movies --region=$REGION --project=$PROJECT --wait 2>/dev/null || \
  echo "Seed job may not exist yet — run manually: gcloud run jobs execute seed-movies --region=$REGION --project=$PROJECT"

# 6. Create Firestore index
echo "--- Creating Firestore index..."
gcloud firestore indexes composite create \
  --collection-group=reviews \
  --field-config field-path=movieId,order=ascending \
  --field-config field-path=createdAt,order=descending \
  --project=$PROJECT 2>/dev/null || true

echo ""
echo "=== Deploy Complete ==="
terraform output
echo ""
echo "Run the frontend:"
echo "  cd ../movies-frontend && npm install && npm run dev"
