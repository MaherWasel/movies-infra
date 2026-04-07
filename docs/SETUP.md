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

### Step 2 — Enable GCP APIs (first time only)

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
```

### Step 3 — Deploy everything

```bash
cd movies-infra
./scripts/deploy.sh
```

This single script handles: state bucket, Terraform config, Artifact Registry, Docker image builds, full infrastructure deploy, database seeding, and Firestore indexes. Takes ~10-15 minutes.

### Step 4 — Run frontend

```bash
cd ../movies-frontend
npm install
npm run dev
```

Open http://localhost:5173 and sign in with Google.

---

## Teardown Everything

```bash
cd movies-infra
./scripts/destroy.sh
```

---

## Rebuild After Teardown

Clone repos → `./scripts/deploy.sh` → `npm run dev`. That's it.

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

### Part A — Destroy Everything

```bash
cd movies-infra
./scripts/destroy.sh
```

That's it. All GCP resources gone, all local code deleted.

### Part B — Restore Everything (~10-15 minutes)

```bash
# Clone repos
git clone https://github.com/MaherWasel/movies-movie-service.git
git clone https://github.com/MaherWasel/movies-review-service.git
git clone https://github.com/MaherWasel/movies-infra.git
git clone https://github.com/MaherWasel/movies-frontend.git

# Deploy everything with one script
cd movies-infra
./scripts/deploy.sh

# Run frontend
cd ../movies-frontend
npm install && npm run dev
```

Open http://localhost:5173 — fully functional.

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
