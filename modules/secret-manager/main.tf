variable "project_id" {
  type = string
}

variable "firebase_project_id" {
  type = string
}

variable "redis_host" {
  type    = string
  default = ""
}

variable "redis_port" {
  type    = string
  default = "6379"
}

variable "pubsub_topic" {
  type    = string
  default = "review-events"
}

variable "pubsub_subscription" {
  type    = string
  default = "review-events-sub"
}

# Firebase project ID
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

# Redis host
resource "google_secret_manager_secret" "redis_host" {
  project   = var.project_id
  secret_id = "redis-host"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_host" {
  secret      = google_secret_manager_secret.redis_host.id
  secret_data = var.redis_host
}

# Redis port
resource "google_secret_manager_secret" "redis_port" {
  project   = var.project_id
  secret_id = "redis-port"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "redis_port" {
  secret      = google_secret_manager_secret.redis_port.id
  secret_data = var.redis_port
}

# Pub/Sub topic name
resource "google_secret_manager_secret" "pubsub_topic" {
  project   = var.project_id
  secret_id = "pubsub-topic"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pubsub_topic" {
  secret      = google_secret_manager_secret.pubsub_topic.id
  secret_data = var.pubsub_topic
}

# Pub/Sub subscription name
resource "google_secret_manager_secret" "pubsub_subscription" {
  project   = var.project_id
  secret_id = "pubsub-subscription"

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "pubsub_subscription" {
  secret      = google_secret_manager_secret.pubsub_subscription.id
  secret_data = var.pubsub_subscription
}

output "firebase_secret_name" {
  value = google_secret_manager_secret.firebase_project.name
}

output "redis_host_secret_name" {
  value = google_secret_manager_secret.redis_host.name
}

output "redis_port_secret_name" {
  value = google_secret_manager_secret.redis_port.name
}

output "pubsub_topic_secret_name" {
  value = google_secret_manager_secret.pubsub_topic.name
}

output "pubsub_subscription_secret_name" {
  value = google_secret_manager_secret.pubsub_subscription.name
}
