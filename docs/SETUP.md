# Setup Guide

**GCP Project:** `project-e005e972-f26f-4d68-b51` | **Region:** `me-central1`

---

## Prerequisites (one-time, already done)

These are already set up and live outside the repos. You just need the tools:

```bash
# Install tools (macOS)
brew install gh terraform
brew install --cask google-cloud-sdk

# Authenticate
gh auth login
gcloud auth login
gcloud auth application-default login
gcloud config set project project-e005e972-f26f-4d68-b51
```

---

## Deploy from Scratch

### Step 1 — Clone repos

```bash
git clone https://github.com/MaherWasel/movies-movie-service.git
git clone https://github.com/MaherWasel/movies-review-service.git
git clone https://github.com/MaherWasel/movies-infra.git
git clone https://github.com/MaherWasel/movies-frontend.git
```

### Step 2 — Enable APIs + create state bucket

```bash
export PROJECT=project-e005e972-f26f-4d68-b51

for api in compute.googleapis.com run.googleapis.com firestore.googleapis.com \
  pubsub.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  redis.googleapis.com apigateway.googleapis.com servicecontrol.googleapis.com \
  servicemanagement.googleapis.com cloudscheduler.googleapis.com \
  secretmanager.googleapis.com vpcaccess.googleapis.com iam.googleapis.com \
  firebase.googleapis.com identitytoolkit.googleapis.com; do
  gcloud services enable "$api" --project=$PROJECT
done

gsutil mb -l me-central1 gs://movies-infra-tfstate 2>/dev/null || true
```

### Step 3 — Build Docker images

```bash
cd movies-infra
cat > terraform.tfvars << 'EOF'
project_id           = "project-e005e972-f26f-4d68-b51"
region               = "me-central1"
github_owner         = "MaherWasel"
firebase_project_id  = "project-e005e972-f26f-4d68-b51"
redis_tier           = "BASIC"
redis_memory_size_gb = 1
EOF

terraform init
terraform apply -target=module.apis -target=module.artifact_registry -auto-approve

cd ../movies-movie-service
gcloud builds submit --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/movie-service:latest \
  --region=me-central1 --project=$PROJECT

cd ../movies-review-service
gcloud builds submit --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/review-service:latest \
  --region=me-central1 --project=$PROJECT
gcloud builds submit --config=cloudbuild-worker.yaml --region=me-central1 --project=$PROJECT
```

### Step 4 — Deploy all infrastructure

```bash
cd ../movies-infra

terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)" 2>/dev/null || true

terraform apply -auto-approve
```

Takes ~8-10 minutes. When done, note the output URLs.

### Step 5 — Seed movies + run frontend

```bash
gcloud run jobs execute seed-movies --region=me-central1 --project=$PROJECT

cd ../movies-frontend
npm install
npm run dev
```

Open http://localhost:5173 and sign in with Google.

---

## Teardown Everything

```bash
export PROJECT=project-e005e972-f26f-4d68-b51

cd movies-infra
terraform destroy -auto-approve

gsutil rm -r gs://movies-infra-tfstate
gcloud firestore databases delete --database="(default)" --project=$PROJECT --quiet 2>/dev/null || true
```

---

## Rebuild After Teardown

Same steps as "Deploy from Scratch" above — clone, enable APIs, build images, `terraform apply`, seed, run frontend. Everything is defined in code.

---

## CI/CD Setup (one-time)

Already configured. Every push to `main` on movie-service or review-service triggers GitHub Actions to build and deploy to Cloud Run automatically. If you need to set it up on a new GCP project:

```bash
export PROJECT=project-e005e972-f26f-4d68-b51
SA="github-actions-sa@$PROJECT.iam.gserviceaccount.com"

# Create Workload Identity Pool
gcloud iam workload-identity-pools create "github-pool" \
  --location="global" --display-name="GitHub Actions Pool" --project=$PROJECT

gcloud iam workload-identity-pools providers create-oidc "github-provider" \
  --location="global" --workload-identity-pool="github-pool" \
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" \
  --attribute-condition="assertion.repository_owner=='MaherWasel'" \
  --issuer-uri="https://token.actions.githubusercontent.com" --project=$PROJECT

# Create service account + permissions
gcloud iam service-accounts create github-actions-sa --display-name="GitHub Actions Deploy" --project=$PROJECT

for role in roles/run.admin roles/artifactregistry.writer roles/iam.serviceAccountUser roles/cloudbuild.builds.editor; do
  gcloud projects add-iam-policy-binding $PROJECT --member="serviceAccount:$SA" --role="$role" --condition=None
done

POOL_ID=$(gcloud iam workload-identity-pools describe github-pool \
  --location=global --project=$PROJECT --format="value(name)")

for REPO in movies-movie-service movies-review-service movies-frontend; do
  gcloud iam service-accounts add-iam-policy-binding $SA \
    --role="roles/iam.workloadIdentityUser" \
    --member="principalSet://iam.googleapis.com/$POOL_ID/attribute.repository/MaherWasel/$REPO" \
    --project=$PROJECT
done
```

---

## Live Demo: Destroy and Restore

This section is for the live demonstration where you must delete the entire cloud environment and restore it to a fully functional state within minutes.

### Part A — Destroy Everything (run during demo)

```bash
export PROJECT=project-e005e972-f26f-4d68-b51

# 1. Destroy all GCP infrastructure
cd movies-infra
terraform destroy -auto-approve

# 2. Delete Terraform state
gsutil rm -r gs://movies-infra-tfstate

# 3. Delete all local repos
cd ..
rm -rf movies-movie-service movies-review-service movies-infra movies-frontend
```

At this point: no Cloud Run services, no Redis, no Pub/Sub, no API Gateway, no code on disk. Everything is gone.

### Part B — Restore Everything (~10-15 minutes)

```bash
export PROJECT=project-e005e972-f26f-4d68-b51

# 1. Clone all repos from GitHub
git clone https://github.com/MaherWasel/movies-movie-service.git
git clone https://github.com/MaherWasel/movies-review-service.git
git clone https://github.com/MaherWasel/movies-infra.git
git clone https://github.com/MaherWasel/movies-frontend.git

# 2. Re-create Terraform state bucket
gsutil mb -l me-central1 gs://movies-infra-tfstate

# 3. Configure Terraform
cd movies-infra
cat > terraform.tfvars << 'EOF'
project_id           = "project-e005e972-f26f-4d68-b51"
region               = "me-central1"
github_owner         = "MaherWasel"
firebase_project_id  = "project-e005e972-f26f-4d68-b51"
redis_tier           = "BASIC"
redis_memory_size_gb = 1
EOF

# 4. Create Artifact Registry first (images need a place to go)
terraform init
terraform apply -target=module.apis -target=module.artifact_registry -auto-approve

# 5. Build and push all Docker images
cd ../movies-movie-service
gcloud builds submit --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/movie-service:latest \
  --region=me-central1 --project=$PROJECT

cd ../movies-review-service
gcloud builds submit --tag me-central1-docker.pkg.dev/$PROJECT/movies-docker/review-service:latest \
  --region=me-central1 --project=$PROJECT
gcloud builds submit --config=cloudbuild-worker.yaml --region=me-central1 --project=$PROJECT

# 6. Deploy all infrastructure
cd ../movies-infra
terraform import module.firestore.google_firestore_database.main \
  "projects/$PROJECT/databases/(default)" 2>/dev/null || true
terraform apply -auto-approve

# 7. Seed movie data
gcloud run jobs execute seed-movies --region=me-central1 --project=$PROJECT

# 8. Run frontend
cd ../movies-frontend
npm install
npm run dev
```

Open http://localhost:5173 — the app is fully functional again. Sign in with Google, browse movies, write reviews, like/dislike.

### What gets restored:
- 3 Cloud Run services (movie-service, review-service, review-worker)
- Memorystore Redis with VPC Connector
- Cloud Pub/Sub topic + subscription
- API Gateway with JWT validation
- Cloud Scheduler nightly job
- Secret Manager secrets
- IAM service accounts (least-privilege)
- Artifact Registry with Docker images
- CI/CD (GitHub Actions — already configured, no setup needed)
- Firestore data (seeded fresh)

### Why it works:
- **All infrastructure is code** — Terraform provisions everything from `main.tf`
- **All application code is in Git** — clone and build
- **No manual console steps** — everything is scripted
- **CI/CD survives** — Workload Identity Federation and GitHub Actions workflows are in the repos
- **Database is seedable** — `seed-movies` Cloud Run Job populates initial data

---

## Troubleshooting

| Error | Fix |
|-------|-----|
| `Image not found` on terraform apply | Build images first (Step 3) |
| `Database already exists` | `terraform import module.firestore.google_firestore_database.main "projects/$PROJECT/databases/(default)"` |
| CORS errors | Services already have CORS middleware. Push to main to redeploy. |
| `origin_mismatch` on Google sign-in | Add `http://localhost:5173` to OAuth client origins in GCP Console > APIs & Credentials. Wait 5 min. |
| GitHub Actions auth fails | Run the CI/CD setup above |
