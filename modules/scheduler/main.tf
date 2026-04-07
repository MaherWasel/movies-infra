variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "movie_service_url" {
  type = string
}

variable "scheduler_sa_email" {
  type = string
}

# Nightly health/seed check job
resource "google_cloud_scheduler_job" "nightly_check" {
  project     = var.project_id
  name        = "nightly-seed-check"
  description = "Nightly check to verify movie seed data and service health"
  region      = var.region
  schedule    = "0 2 * * *"
  time_zone   = "Asia/Riyadh"

  http_target {
    http_method = "GET"
    uri         = "${var.movie_service_url}/health"

    oidc_token {
      service_account_email = var.scheduler_sa_email
    }
  }

  retry_config {
    retry_count = 3
  }
}
