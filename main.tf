# Enable required GCP APIs
module "apis" {
  source     = "./modules/apis"
  project_id = var.project_id
}

# IAM — service accounts and roles
module "iam" {
  source     = "./modules/iam"
  project_id = var.project_id

  depends_on = [module.apis]
}

# Secret Manager — store sensitive config
module "secret_manager" {
  source              = "./modules/secret-manager"
  project_id          = var.project_id
  firebase_project_id = var.firebase_project_id
  redis_host          = module.memorystore.redis_host
  redis_port          = tostring(module.memorystore.redis_port)
  pubsub_topic        = module.pubsub.topic_name
  pubsub_subscription = module.pubsub.subscription_name

  depends_on = [module.apis, module.memorystore, module.pubsub]
}

# Firestore database
module "firestore" {
  source     = "./modules/firestore"
  project_id = var.project_id
  region     = var.region

  depends_on = [module.apis]
}

# Memorystore Redis
module "memorystore" {
  source           = "./modules/memorystore"
  project_id       = var.project_id
  region           = var.region
  tier             = var.redis_tier
  memory_size_gb   = var.redis_memory_size_gb

  depends_on = [module.apis]
}

# Artifact Registry
module "artifact_registry" {
  source     = "./modules/artifact-registry"
  project_id = var.project_id
  region     = var.region

  depends_on = [module.apis]
}

# Pub/Sub topic and subscription
module "pubsub" {
  source     = "./modules/pubsub"
  project_id = var.project_id

  depends_on = [module.apis]
}

# Cloud Run services
module "cloud_run" {
  source                  = "./modules/cloud-run"
  project_id              = var.project_id
  region                  = var.region
  movie_service_image     = "${var.region}-docker.pkg.dev/${var.project_id}/movies-docker/movie-service:latest"
  review_service_image    = "${var.region}-docker.pkg.dev/${var.project_id}/movies-docker/review-service:latest"
  review_worker_image     = "${var.region}-docker.pkg.dev/${var.project_id}/movies-docker/review-worker:latest"
  redis_host              = module.memorystore.redis_host
  redis_port              = module.memorystore.redis_port
  movie_service_sa_email  = module.iam.movie_service_sa_email
  review_service_sa_email = module.iam.review_service_sa_email
  worker_sa_email         = module.iam.worker_sa_email
  vpc_connector_name      = module.memorystore.vpc_connector_name
  pubsub_topic            = module.pubsub.topic_name
  pubsub_subscription     = module.pubsub.subscription_name

  # Secret Manager references for Cloud Run env injection
  firebase_secret_name            = module.secret_manager.firebase_secret_name
  redis_host_secret_name          = module.secret_manager.redis_host_secret_name
  redis_port_secret_name          = module.secret_manager.redis_port_secret_name
  pubsub_topic_secret_name        = module.secret_manager.pubsub_topic_secret_name
  pubsub_subscription_secret_name = module.secret_manager.pubsub_subscription_secret_name
  node_env_secret_name            = module.secret_manager.node_env_secret_name

  depends_on = [module.apis, module.artifact_registry, module.memorystore, module.pubsub, module.iam, module.secret_manager]
}

# API Gateway
module "api_gateway" {
  source                   = "./modules/api-gateway"
  project_id               = var.project_id
  region                   = var.region
  firebase_project_id      = var.firebase_project_id
  movie_service_url        = module.cloud_run.movie_service_url
  review_service_url       = module.cloud_run.review_service_url

  depends_on = [module.cloud_run]
}

# Cloud Scheduler
module "scheduler" {
  source                = "./modules/scheduler"
  project_id            = var.project_id
  region                = var.region
  movie_service_url     = module.cloud_run.movie_service_url
  scheduler_sa_email    = module.iam.scheduler_sa_email

  depends_on = [module.cloud_run, module.iam]
}

# Cloud Build triggers — requires manual GitHub App connection first.
# After connecting GitHub in Cloud Build console, uncomment this block.
# module "cloud_build" {
#   source       = "./modules/cloud-build"
#   project_id   = var.project_id
#   region       = var.region
#   github_owner = var.github_owner
#
#   depends_on = [module.apis, module.artifact_registry]
# }
