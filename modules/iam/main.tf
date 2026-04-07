variable "project_id" {
  type = string
}

# Movie Service SA
resource "google_service_account" "movie_service" {
  project      = var.project_id
  account_id   = "movie-service-sa"
  display_name = "Movie Service"
}

# Review Service SA
resource "google_service_account" "review_service" {
  project      = var.project_id
  account_id   = "review-service-sa"
  display_name = "Review Service"
}

# Worker SA
resource "google_service_account" "worker" {
  project      = var.project_id
  account_id   = "review-worker-sa"
  display_name = "Review Worker"
}

# Scheduler SA
resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "scheduler-sa"
  display_name = "Cloud Scheduler"
}

# Cloud Build SA
resource "google_service_account" "cloud_build" {
  project      = var.project_id
  account_id   = "cloud-build-sa"
  display_name = "Cloud Build"
}

# --- IAM Bindings ---

# Movie service: Firestore + Redis + Secret Manager
resource "google_project_iam_member" "movie_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.movie_service.email}"
}

resource "google_project_iam_member" "movie_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.movie_service.email}"
}

# Review service: Firestore + Pub/Sub publisher + Secret Manager
resource "google_project_iam_member" "review_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.review_service.email}"
}

resource "google_project_iam_member" "review_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.review_service.email}"
}

resource "google_project_iam_member" "review_secrets" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.review_service.email}"
}

# Worker: Firestore + Pub/Sub subscriber
resource "google_project_iam_member" "worker_firestore" {
  project = var.project_id
  role    = "roles/datastore.user"
  member  = "serviceAccount:${google_service_account.worker.email}"
}

resource "google_project_iam_member" "worker_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.worker.email}"
}

# Scheduler: invoke Cloud Run
resource "google_project_iam_member" "scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Build: deploy to Cloud Run + push to Artifact Registry
resource "google_project_iam_member" "build_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "build_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.writer"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "build_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Outputs
output "movie_service_sa_email" {
  value = google_service_account.movie_service.email
}

output "review_service_sa_email" {
  value = google_service_account.review_service.email
}

output "worker_sa_email" {
  value = google_service_account.worker.email
}

output "scheduler_sa_email" {
  value = google_service_account.scheduler.email
}

output "cloud_build_sa_email" {
  value = google_service_account.cloud_build.email
}
