variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "movie_service_image" {
  type = string
}

variable "review_service_image" {
  type = string
}

variable "review_worker_image" {
  type = string
}

variable "redis_host" {
  type = string
}

variable "redis_port" {
  type = number
}

variable "movie_service_sa_email" {
  type = string
}

variable "review_service_sa_email" {
  type = string
}

variable "worker_sa_email" {
  type = string
}

variable "vpc_connector_name" {
  type = string
}

variable "pubsub_topic" {
  type = string
}

variable "pubsub_subscription" {
  type = string
}

variable "firebase_secret_name" {
  type = string
}

variable "redis_host_secret_name" {
  type = string
}

variable "redis_port_secret_name" {
  type = string
}

variable "pubsub_topic_secret_name" {
  type = string
}

variable "pubsub_subscription_secret_name" {
  type = string
}

# Movie Service
resource "google_cloud_run_v2_service" "movie_service" {
  project  = var.project_id
  name     = "movie-service"
  location = var.region

  template {
    service_account = var.movie_service_sa_email

    vpc_access {
      connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.movie_service_image

      ports {
        container_port = 8080
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name = "GCP_PROJECT_ID"
        value_source {
          secret_key_ref {
            secret  = var.firebase_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_HOST"
        value_source {
          secret_key_ref {
            secret  = var.redis_host_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_PORT"
        value_source {
          secret_key_ref {
            secret  = var.redis_port_secret_name
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        period_seconds = 30
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
  }
}

# Review Service
resource "google_cloud_run_v2_service" "review_service" {
  project  = var.project_id
  name     = "review-service"
  location = var.region

  template {
    service_account = var.review_service_sa_email

    vpc_access {
      connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.review_service_image

      ports {
        container_port = 8080
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name = "GCP_PROJECT_ID"
        value_source {
          secret_key_ref {
            secret  = var.firebase_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_HOST"
        value_source {
          secret_key_ref {
            secret  = var.redis_host_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "REDIS_PORT"
        value_source {
          secret_key_ref {
            secret  = var.redis_port_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "PUBSUB_TOPIC"
        value_source {
          secret_key_ref {
            secret  = var.pubsub_topic_secret_name
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }

      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 5
        period_seconds        = 5
        failure_threshold     = 3
      }

      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        period_seconds = 30
      }
    }

    scaling {
      min_instance_count = 0
      max_instance_count = 5
    }
  }
}

# Review Worker (Pub/Sub consumer)
resource "google_cloud_run_v2_service" "review_worker" {
  project  = var.project_id
  name     = "review-worker"
  location = var.region

  template {
    service_account = var.worker_sa_email

    vpc_access {
      connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
      egress    = "PRIVATE_RANGES_ONLY"
    }

    containers {
      image = var.review_worker_image

      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name = "GCP_PROJECT_ID"
        value_source {
          secret_key_ref {
            secret  = var.firebase_secret_name
            version = "latest"
          }
        }
      }
      env {
        name = "PUBSUB_SUBSCRIPTION"
        value_source {
          secret_key_ref {
            secret  = var.pubsub_subscription_secret_name
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }

    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }
  }
}

# Allow unauthenticated access to movie & review services (Gateway handles auth)
resource "google_cloud_run_v2_service_iam_member" "movie_public" {
  project  = var.project_id
  name     = google_cloud_run_v2_service.movie_service.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_cloud_run_v2_service_iam_member" "review_public" {
  project  = var.project_id
  name     = google_cloud_run_v2_service.review_service.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Run Job — one-off seed process (Factor 12: Admin Processes)
resource "google_cloud_run_v2_job" "seed_movies" {
  project  = var.project_id
  name     = "seed-movies"
  location = var.region

  template {
    template {
      service_account = var.movie_service_sa_email

      vpc_access {
        connector = "projects/${var.project_id}/locations/${var.region}/connectors/${var.vpc_connector_name}"
        egress    = "PRIVATE_RANGES_ONLY"
      }

      containers {
        image   = var.movie_service_image
        command = ["node", "src/seed.js"]

        env {
          name  = "NODE_ENV"
          value = "production"
        }
        env {
          name = "GCP_PROJECT_ID"
          value_source {
            secret_key_ref {
              secret  = var.firebase_secret_name
              version = "latest"
            }
          }
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }

      max_retries = 1
      timeout     = "300s"
    }
  }
}

output "movie_service_url" {
  value = google_cloud_run_v2_service.movie_service.uri
}

output "review_service_url" {
  value = google_cloud_run_v2_service.review_service.uri
}

output "review_worker_url" {
  value = google_cloud_run_v2_service.review_worker.uri
}
