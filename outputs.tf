output "movie_service_url" {
  description = "URL of the Movie Service on Cloud Run"
  value       = module.cloud_run.movie_service_url
}

output "review_service_url" {
  description = "URL of the Review Service on Cloud Run"
  value       = module.cloud_run.review_service_url
}

output "api_gateway_url" {
  description = "URL of the API Gateway"
  value       = module.api_gateway.gateway_url
}

output "redis_host" {
  description = "Redis host IP"
  value       = module.memorystore.redis_host
  sensitive   = true
}

output "artifact_registry_url" {
  description = "Artifact Registry repository URL"
  value       = module.artifact_registry.repository_url
}
