variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

resource "google_artifact_registry_repository" "docker" {
  project       = var.project_id
  location      = var.region
  repository_id = "movies-docker"
  format        = "DOCKER"
  description   = "Docker images for Movies app services"
}

output "repository_url" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.docker.repository_id}"
}
