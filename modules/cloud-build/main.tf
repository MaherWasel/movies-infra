variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "github_owner" {
  type = string
}

# Cloud Build trigger for movie-service (webhook-based, no GitHub App required)
resource "google_cloudbuild_trigger" "movie_service" {
  project  = var.project_id
  name     = "movie-service-deploy"
  location = var.region

  source_to_build {
    uri       = "https://github.com/${var.github_owner}/movies-movie-service"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }

  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = "https://github.com/${var.github_owner}/movies-movie-service"
    revision  = "refs/heads/main"
    repo_type = "GITHUB"
  }

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

  source_to_build {
    uri       = "https://github.com/${var.github_owner}/movies-review-service"
    ref       = "refs/heads/main"
    repo_type = "GITHUB"
  }

  git_file_source {
    path      = "cloudbuild.yaml"
    uri       = "https://github.com/${var.github_owner}/movies-review-service"
    revision  = "refs/heads/main"
    repo_type = "GITHUB"
  }

  substitutions = {
    _REGION    = var.region
    _REPO_NAME = "movies-docker"
  }
}
