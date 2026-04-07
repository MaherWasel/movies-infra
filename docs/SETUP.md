# Complete Setup Guide — From Scratch to Production

This guide covers deploying the entire Movies Review system from zero on a fresh GCP project, as well as tearing it down and rebuilding from cloned repos.

---

## Prerequisites

Install these tools on your machine:

```bash
# macOS (Homebrew)
brew install gh terraform
brew install --cask google-cloud-sdk

# Or install manually:
# - gcloud: https://cloud.google.com/sdk/docs/install
# - terraform: https://developer.hashicorp.com/terraform/install
# - gh: https://cli.github.com/
# - node 20+: https://nodejs.org/
```

---

## Part 1: Fresh GCP Project Setup

### 1.1 Authenticate

```bash
# GitHub CLI
gh auth login

# Google Cloud CLI
gcloud auth login
gcloud auth application-default login

# Set your project
gcloud config set project YOUR_PROJECT_ID
```

### 1.2 Create Terraform State Bucket

```bash
gsutil mb -l me-central1 gs://movies-infra-tfstate
```

### 1.3 Clone All Repos

```bash
git clone https://github.com/MaherWasel/movies-movie-service.git
git clone https://github.com/MaherWasel/movies-review-service.git
git clone https://github.com/MaherWasel/movies-infra.git
git clone https://github.com/MaherWasel/movies-frontend.git
```

### 1.4 Configure Terraform

```bash
cd movies-infra
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars` with your values:

```hcl
project_id           = "your-gcp-project-id"
region               = "me-central1"
github_owner         = "MaherWasel"
firebase_project_id  = "your-gcp-project-id"
redis_tier           = "BASIC"
redis_memory_size_gb = 1
```

### 1.5 Enable GCP APIs

```bash
PROJECT=your-gcp-project-id
for api in compute.googleapis.com run.googleapis.com firestore.googleapis.com \
  pubsub.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  redis.googleapis.com apigateway.googleapis.com servicecontrol.googleapis.com \
  servicemanagement.googleapis.com cloudscheduler.googleapis.com \
  secretmanager.googleapis.com vpcaccess.googleapis.com iam.googleapis.com; do
  gcloud services enable "$api" --project="$PROJECT"
done
```

### 1.6 Build & Push Docker Images

Images must exist in Artifact Registry before Terraform can deploy Cloud Run services. First, initialize Terraform to create the Artifact Registry:

```bash
cd movies-infra
terraform init
terraform apply -target=module.apis -target=module.artifact_registry -auto-approve
```

Then build and push all images via Cloud Build:

```bash
# Movie Service
cd ../movies-movie-service
gcloud builds submit \
  --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/movie-service:latest \
  --region=me-central1 --project=$PROJECT

# Review Service API
cd ../movies-review-service
gcloud builds submit \
  --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/review-service:latest \
  --region=me-central1 --project=$PROJECT

# Review Worker
gcloud builds submit \
  --config=cloudbuild-worker.yaml \
  --region=me-central1 --project=$PROJECT
```

### 1.7 Import Existing Firestore (if applicable)

If the GCP project already has a Firestore database:

```bash
cd ../movies-infra
terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)"
```

### 1.8 Apply All Infrastructure

```bash
terraform apply -auto-approve
```

This provisions: Memorystore Redis, VPC Connector, Cloud Run services (3), Pub/Sub topic + subscription, API Gateway, Cloud Scheduler, Secret Manager secrets, IAM service accounts.

**Expected time**: ~8-10 minutes (Redis and VPC Connector are the slowest).

### 1.9 Seed Movie Data

```bash
gcloud run jobs execute seed-movies --region=me-central1 --project=$PROJECT
```

### 1.10 Set Up CI/CD (GitHub Actions + Workload Identity)

```bash
# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" \
  --display-name="GitHub Actions Pool" \
  --project=$PROJECT

# Create OIDC Provider
gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" \
  --workload-identity-pool="github-pool" \
  --display-name="GitHub Provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository,attribute.actor=assertion.actor" \
  --attribute-condition="assertion.repository_owner=='MaherWasel'" \
  --issuer-uri="https://token.actions.githubusercontent.com" \
  --project=$PROJECT

# Create Service Account for GitHub Actions
gcloud iam service-accounts create github-actions-sa \
  --display-name="GitHub Actions Deploy" \
  --project=$PROJECT

SA="github-actions-sa@$PROJECT.iam.gserviceaccount.com"

# Grant deploy permissions
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA" --role="roles/run.admin"
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA" --role="roles/artifactregistry.writer"
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA" --role="roles/iam.serviceAccountUser"
gcloud projects add-iam-policy-binding $PROJECT \
  --member="serviceAccount:$SA" --role="roles/cloudbuild.builds.editor"

# Bind Workload Identity to repos
POOL_ID=$(gcloud iam workload-identity-pools describe github-pool \
  --location=global --project=$PROJECT --format="value(name)")

for REPO in movies-movie-service movies-review-service movies-frontend; do
  gcloud iam service-accounts add-iam-policy-binding $SA \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL_ID/attribute.repository/MaherWasel/$REPO" \
    --project=$PROJECT
done
```

### 1.11 Set Up Firebase Auth

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Add your GCP project (or create a new Firebase project linked to it)
3. Enable **Authentication** → **Sign-in method** → **Google**
4. Note your Firebase config values (API key, auth domain, project ID)

### 1.12 Configure Frontend

```bash
cd movies-frontend
cp .env.example .env
```

Edit `.env`:

```
VITE_API_GATEWAY_URL=https://movies-gateway-XXXXX.ew.gateway.dev
VITE_FIREBASE_API_KEY=your-firebase-api-key
VITE_FIREBASE_AUTH_DOMAIN=your-project.firebaseapp.com
VITE_FIREBASE_PROJECT_ID=your-project-id
```

Get the API Gateway URL from Terraform output:

```bash
cd ../movies-infra
terraform output api_gateway_url
```

### 1.13 Run Frontend Locally

```bash
cd movies-frontend
npm install
npm run dev
```

---

## Part 2: Verify Deployment

### Check Cloud Run Services

```bash
gcloud run services list --region=me-central1 --project=$PROJECT
```

Expected output:
```
SERVICE         REGION       URL                                    LAST DEPLOYED
movie-service   me-central1  https://movie-service-xxx.a.run.app    ...
review-service  me-central1  https://review-service-xxx.a.run.app   ...
review-worker   me-central1  https://review-worker-xxx.a.run.app    ...
```

### Test Health Endpoints

```bash
curl https://movie-service-xxx.a.run.app/health
curl https://review-service-xxx.a.run.app/health
```

### Test CI/CD

Push a trivial change to either service repo and verify the GitHub Actions workflow runs:

```bash
cd movies-movie-service
echo "" >> README.md
git add -A && git commit -m "test: trigger CI/CD" && git push
gh run list --limit 1  # Should show in_progress or completed
```

---

## Part 3: Complete Teardown

To destroy all infrastructure:

```bash
cd movies-infra
terraform destroy -auto-approve
```

This removes: Cloud Run services, Redis, VPC Connector, Pub/Sub, API Gateway, Scheduler, Secret Manager secrets, IAM service accounts, Artifact Registry.

**Note**: Firestore databases cannot be deleted via Terraform. To remove:
```bash
gcloud firestore databases delete --database="(default)" --project=$PROJECT
```

To also remove the Terraform state bucket:
```bash
gsutil rm -r gs://movies-infra-tfstate
```

To remove Workload Identity (CI/CD):
```bash
gcloud iam workload-identity-pools delete github-pool --location=global --project=$PROJECT
gcloud iam service-accounts delete github-actions-sa@$PROJECT.iam.gserviceaccount.com --project=$PROJECT
```

---

## Part 4: Rebuild After Teardown

If you've torn everything down and want to rebuild from the cloned repos:

### 4.1 Re-create state bucket
```bash
gsutil mb -l me-central1 gs://movies-infra-tfstate
```

### 4.2 Re-enable APIs
```bash
# Run the same API enable loop from Step 1.5
```

### 4.3 Initialize and apply Terraform (partial first)
```bash
cd movies-infra
terraform init
terraform apply -target=module.apis -target=module.artifact_registry -auto-approve
```

### 4.4 Rebuild and push Docker images
```bash
# Run the same gcloud builds submit commands from Step 1.6
```

### 4.5 Apply full infrastructure
```bash
# If Firestore already exists, import it first:
terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)"

terraform apply -auto-approve
```

### 4.6 Re-seed data
```bash
gcloud run jobs execute seed-movies --region=me-central1 --project=$PROJECT
```

### 4.7 Re-setup CI/CD
```bash
# Run the Workload Identity setup from Step 1.10
```

### 4.8 Verify
```bash
# Run the verification steps from Part 2
```

---

## Troubleshooting

### "Image not found" during Terraform apply
Docker images must exist in Artifact Registry before Cloud Run can deploy. Build and push images first (Step 1.6), then re-run `terraform apply`.

### "Database already exists" error
Import the existing Firestore database into Terraform state:
```bash
terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)"
```

### "PORT is a reserved env name"
Cloud Run v2 auto-injects PORT. Do not set it in Terraform env vars.

### Redis connection errors on Cloud Run
Ensure the VPC Connector is created and Cloud Run services have `vpc_access` configured. Redis is not publicly accessible — it requires the VPC Connector.

### GitHub Actions auth fails
Verify Workload Identity Federation is set up correctly:
```bash
gcloud iam workload-identity-pools providers describe github-provider \
  --workload-identity-pool=github-pool --location=global --project=$PROJECT
```

### API Gateway returns 401
Ensure Firebase Auth is configured and the JWT `aud` claim matches the `x-google-audiences` in the OpenAPI spec.
