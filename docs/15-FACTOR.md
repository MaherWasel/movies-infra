# 15-Factor App Compliance

## 1. Codebase
Each service lives in its own GitHub repository (`movies-movie-service`, `movies-review-service`, `movies-infra`). Each repo is independently versioned, built, and deployed. One codebase per service, tracked in Git.

## 2. Dependencies
All dependencies are declared in `package.json` and pinned via `package-lock.json`. Docker images use `npm ci` to install from the lockfile. No system-level package dependencies exist outside the Node.js Alpine base image. Terraform providers are declared in `providers.tf` with version constraints.

## 3. Config
All configuration is injected via environment variables (`src/config.js`). No hardcoded project IDs, hosts, or credentials exist in code. Cloud Run env vars are set via Terraform (`modules/cloud-run/main.tf`). Sensitive values are stored in Secret Manager (`modules/secret-manager/main.tf`).

## 4. Backing Services
Firestore, Redis (Memorystore), and Pub/Sub are treated as attached resources configured through environment variables (`GCP_PROJECT_ID`, `REDIS_HOST`, `REDIS_PORT`, `PUBSUB_TOPIC`). Swapping a backing service requires only changing env vars — no code changes needed.

## 5. Build, Release, Run
Strictly separated via Cloud Build (`cloudbuild.yaml`). Build: Docker multi-stage build creates the image. Release: image is tagged with `SHORT_SHA` and pushed to Artifact Registry. Run: Cloud Run deploys the tagged image. No code changes happen at runtime.

## 6. Processes
Cloud Run instances are completely stateless. No local filesystem state, no sticky sessions. All state lives in Firestore (persistent) or Redis (cache). Each request can be served by any instance.

## 7. Port Binding
Each service self-contains its HTTP server (Express). The server binds to the `PORT` environment variable (`src/index.js`: `app.listen(config.port)`). Cloud Run injects `PORT=8080`. No external web server (nginx, Apache) is needed.

## 8. Concurrency
Scaling is handled by Cloud Run replicas (`scaling.min_instance_count` / `max_instance_count` in `modules/cloud-run/main.tf`). The app scales horizontally — add more instances, not threads. Each instance handles concurrent requests via Node.js's event loop.

## 9. Disposability
Fast startup: Node.js + Alpine Docker images start in seconds. Graceful shutdown: both services listen for `SIGTERM`, close the HTTP server, drain Redis connections, then exit (`src/index.js`: `shutdown()` function). Cloud Run sends SIGTERM before killing instances.

## 10. Dev/Prod Parity
The same Docker image built by Cloud Build runs locally and in production. Environment differences are isolated to env vars only. `docker run -e PORT=8080 -e REDIS_HOST=localhost ...` works identically to Cloud Run.

## 11. Logs
All services use `pino` for structured JSON logging to stdout (`src/logger.js`). HTTP request logging uses `pino-http`. Cloud Run captures stdout and routes it to Cloud Logging automatically. No file-based logging exists.

## 12. Admin Processes
The seed script (`src/seed.js`) can run as a standalone one-off process (`node src/seed.js`) or as a Cloud Run Job. It is not embedded in the main request path — it runs on startup only if the movies collection is empty, and can also be invoked independently.

## 13. API First
All inter-service communication uses documented REST APIs (see `docs/API.md`). The API Gateway (`modules/api-gateway/openapi.yaml.tpl`) defines the full OpenAPI spec. Services communicate only via HTTP and Pub/Sub — no shared databases or internal RPC.

## 14. Telemetry
Health check endpoints (`/health`) on every service enable uptime monitoring. Structured JSON logs provide observability via Cloud Logging. Cloud Run metrics (request count, latency, CPU) are available in Cloud Monitoring. Cloud Scheduler runs nightly health checks (`modules/scheduler/main.tf`).

## 15. Auth & Security
Firebase Auth with Google Sign-In issues JWTs. API Gateway validates JWTs before routing (`securityDefinitions.firebase` in OpenAPI spec). Validated tokens are cached in Memorystore Redis (`middleware/auth.js`). Secrets are stored in Secret Manager — no plaintext secrets in code. Each service runs with a dedicated least-privilege service account (`modules/iam/main.tf`). Docker containers run as non-root user (`USER appuser` in Dockerfile).
