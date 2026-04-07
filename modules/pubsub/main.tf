variable "project_id" {
  type = string
}

resource "google_pubsub_topic" "review_events" {
  project = var.project_id
  name    = "review-events"
}

resource "google_pubsub_subscription" "review_events_sub" {
  project = var.project_id
  name    = "review-events-sub"
  topic   = google_pubsub_topic.review_events.id

  ack_deadline_seconds = 20

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }

  expiration_policy {
    ttl = "" # never expires
  }
}

output "topic_name" {
  value = google_pubsub_topic.review_events.name
}

output "topic_id" {
  value = google_pubsub_topic.review_events.id
}

output "subscription_name" {
  value = google_pubsub_subscription.review_events_sub.name
}
