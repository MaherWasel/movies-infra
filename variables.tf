variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "me-central1"
}

variable "github_owner" {
  description = "GitHub repository owner"
  type        = string
}

variable "firebase_project_id" {
  description = "Firebase project ID (usually same as GCP project)"
  type        = string
}

variable "redis_tier" {
  description = "Memorystore Redis tier"
  type        = string
  default     = "BASIC"
}

variable "redis_memory_size_gb" {
  description = "Redis memory size in GB"
  type        = number
  default     = 1
}
