variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "tier" {
  type    = string
  default = "BASIC"
}

variable "memory_size_gb" {
  type    = number
  default = 1
}

# VPC connector for Cloud Run to access Redis
resource "google_vpc_access_connector" "connector" {
  project       = var.project_id
  name          = "movies-vpc-connector"
  region        = var.region
  ip_cidr_range = "10.8.0.0/28"
  network       = "default"
}

resource "google_redis_instance" "cache" {
  project            = var.project_id
  name               = "movies-redis"
  region             = var.region
  tier               = var.tier
  memory_size_gb     = var.memory_size_gb
  redis_version      = "REDIS_7_0"
  authorized_network = "projects/${var.project_id}/global/networks/default"

  display_name = "Movies Token Cache"
}

output "redis_host" {
  value = google_redis_instance.cache.host
}

output "redis_port" {
  value = google_redis_instance.cache.port
}

output "vpc_connector_name" {
  value = google_vpc_access_connector.connector.name
}
