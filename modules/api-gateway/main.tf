variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "firebase_project_id" {
  type = string
}

variable "movie_service_url" {
  type = string
}

variable "review_service_url" {
  type = string
}

resource "google_api_gateway_api" "movies" {
  provider = google-beta
  project  = var.project_id
  api_id   = "movies-api"
}

resource "google_api_gateway_api_config" "movies" {
  provider      = google-beta
  project       = var.project_id
  api           = google_api_gateway_api.movies.api_id
  api_config_id = "movies-api-config-v1"

  openapi_documents {
    document {
      path = "openapi.yaml"
      contents = base64encode(templatefile("${path.module}/openapi.yaml.tpl", {
        movie_service_url   = var.movie_service_url
        review_service_url  = var.review_service_url
        firebase_project_id = var.firebase_project_id
      }))
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_api_gateway_gateway" "movies" {
  provider   = google-beta
  project    = var.project_id
  region     = var.region
  api_config = google_api_gateway_api_config.movies.id
  gateway_id = "movies-gateway"
}

output "gateway_url" {
  value = google_api_gateway_gateway.movies.default_hostname
}
