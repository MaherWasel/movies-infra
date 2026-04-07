variable "project_id" {
  type = string
}

variable "firebase_project_id" {
  type = string
}

resource "google_secret_manager_secret" "firebase_project" {
  project   = var.project_id
  secret_id = "firebase-project-id"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "firebase_project" {
  secret      = google_secret_manager_secret.firebase_project.id
  secret_data = var.firebase_project_id
}

resource "google_secret_manager_secret" "redis_config" {
  project   = var.project_id
  secret_id = "redis-connection"

  replication {
    auto {}
  }
}

output "firebase_secret_id" {
  value = google_secret_manager_secret.firebase_project.secret_id
}

output "redis_secret_id" {
  value = google_secret_manager_secret.redis_config.secret_id
}
