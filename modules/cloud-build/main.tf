variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "github_owner" {
  type = string
}

# Cloud Build trigger for movie-service
resource "google_cloudbuild_trigger" "movie_service" {
  project  = var.project_id
  name     = "movie-service-deploy"
  location = var.region

  github {
    owner = var.github_owner
    name  = "movies-movie-service"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _REGION    = var.region
    _REPO_NAME = "movies-docker"
  }
}

# Cloud Build trigger for review-service
resource "google_cloudbuild_trigger" "review_service" {
  project  = var.project_id
  name     = "review-service-deploy"
  location = var.region

  github {
    owner = var.github_owner
    name  = "movies-review-service"

    push {
      branch = "^main$"
    }
  }

  filename = "cloudbuild.yaml"

  substitutions = {
    _REGION    = var.region
    _REPO_NAME = "movies-docker"
  }
}
