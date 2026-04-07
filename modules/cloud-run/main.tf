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
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REDIS_HOST"
        value = var.redis_host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(var.redis_port)
      }
      env {
        name  = "NODE_ENV"
        value = "production"
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
        name  = "PORT"
        value = "8080"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REDIS_HOST"
        value = var.redis_host
      }
      env {
        name  = "REDIS_PORT"
        value = tostring(var.redis_port)
      }
      env {
        name  = "PUBSUB_TOPIC"
        value = var.pubsub_topic
      }
      env {
        name  = "NODE_ENV"
        value = "production"
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
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "PUBSUB_SUBSCRIPTION"
        value = var.pubsub_subscription
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "256Mi"
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

output "movie_service_url" {
  value = google_cloud_run_v2_service.movie_service.uri
}

output "review_service_url" {
  value = google_cloud_run_v2_service.review_service.uri
}

output "review_worker_url" {
  value = google_cloud_run_v2_service.review_worker.uri
}
