variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

# Firestore database already exists in this project (us-central1).
# We import it into state rather than creating it.
resource "google_firestore_database" "main" {
  project     = var.project_id
  name        = "(default)"
  location_id = "us-central1"
  type        = "FIRESTORE_NATIVE"

  lifecycle {
    ignore_changes = [location_id]
  }
}
