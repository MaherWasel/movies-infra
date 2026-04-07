# 15-Factor App Compliance

This document maps every factor to the specific files, configs, and architectural decisions in this system.

---

## 1. Codebase — One codebase per service, tracked in its own GitHub repo

Each microservice lives in its own independently versioned GitHub repository:

- [`movies-movie-service`](https://github.com/MaherWasel/movies-movie-service) — Movie listing API
- [`movies-review-service`](https://github.com/MaherWasel/movies-review-service) — Reviews, likes, and Pub/Sub worker
- [`movies-infra`](https://github.com/MaherWasel/movies-infra) — All infrastructure as Terraform code

Each repo has its own CI/CD pipeline (`.github/workflows/deploy.yml`), its own `Dockerfile`, and can be deployed independently. There is no shared codebase between services — each is a standalone deployable unit.

---

## 2. Dependencies — Explicitly declared, no reliance on system packages

All runtime dependencies are declared in `package.json` and pinned via `package-lock.json` in each service repo. Docker images use `npm ci --omit=dev` to install from the lockfile deterministically.

The base image is `node:20-alpine` — a minimal OS with no extra system packages. No global npm installs or OS-level dependencies are required.

**Terraform** providers are declared in `providers.tf` with version constraints (`~> 5.0` for Google provider).

**Relevant files:**
- `movies-movie-service/package.json`, `package-lock.json`
- `movies-review-service/package.json`, `package-lock.json`
- `movies-infra/providers.tf`

---

## 3. Config — All config via environment variables, injected via Secret Manager and Cloud Run env vars

Zero hardcoded secrets, project IDs, or credentials exist in application code. Every configurable value is read from environment variables in `src/config.js`:

```
PORT, GCP_PROJECT_ID, REDIS_HOST, REDIS_PORT, TOKEN_CACHE_TTL,
PUBSUB_TOPIC, PUBSUB_SUBSCRIPTION, NODE_ENV, LOG_LEVEL
```

Sensitive values (GCP_PROJECT_ID, REDIS_HOST, REDIS_PORT, PUBSUB_TOPIC, PUBSUB_SUBSCRIPTION) are stored in **Google Secret Manager** and injected into Cloud Run containers at runtime using `value_source.secret_key_ref` blocks in Terraform (`modules/cloud-run/main.tf`).

Non-sensitive values (NODE_ENV) are set as plain Cloud Run environment variables.

**Relevant files:**
- `movies-movie-service/src/config.js`
- `movies-review-service/src/config.js`
- `movies-infra/modules/secret-manager/main.tf` — 5 secrets
- `movies-infra/modules/cloud-run/main.tf` — env injection from secrets

---

## 4. Backing Services — Firestore, Redis, Pub/Sub treated as attached resources via config

All backing services are treated as attached resources, swappable by changing environment variables alone:

| Service | Purpose | Config |
|---------|---------|--------|
| **Firestore** | Primary database (movies, reviews, likes collections) | `GCP_PROJECT_ID` |
| **Memorystore Redis** | JWT token validation cache | `REDIS_HOST`, `REDIS_PORT` |
| **Cloud Pub/Sub** | Async event messaging | `PUBSUB_TOPIC`, `PUBSUB_SUBSCRIPTION` |

Each backing service is initialized in a dedicated file (`src/services/firestore.js`, `src/services/redis.js`, `src/services/pubsub.js`) using only environment variable configuration. Swapping Redis from Memorystore to a self-hosted instance requires only changing `REDIS_HOST` — no code changes.

---

## 5. Build, Release, Run — Strictly separated via CI/CD pipeline

The three stages are strictly separated:

- **Build**: Docker multi-stage build creates an immutable image. Stage 1 installs dependencies, Stage 2 copies only production artifacts. (`Dockerfile`)
- **Release**: Image is tagged with the git SHA and `latest`, pushed to Artifact Registry. (`deploy.yml` → `docker push`)
- **Run**: Cloud Run deploys the tagged image. The running container receives only environment variables — no code changes happen at runtime. (`deploy.yml` → `gcloud run services update`)

The CI/CD pipeline is fully automated via GitHub Actions (`.github/workflows/deploy.yml`). Every push to `main` triggers build → push → deploy with zero human intervention.

**Authentication**: GitHub Actions authenticates to GCP via **Workload Identity Federation** — no service account keys are stored anywhere.

---

## 6. Processes — Stateless Cloud Run instances, no local state

Cloud Run instances are completely stateless:

- No local filesystem state is persisted between requests
- No sticky sessions or in-memory caches that can't be lost
- All persistent state lives in Firestore
- Redis is used only as a cache (token validation) — cache misses fall back to Firebase verification (`src/middleware/auth.js`)
- Any instance can serve any request

Cloud Run can scale to zero and back up without data loss.

---

## 7. Port Binding — Each service self-contains its HTTP server and binds to PORT env var

Each service embeds its own HTTP server (Express.js) and binds to the `PORT` environment variable:

```js
// src/index.js
server = app.listen(config.port, () => { ... });

// src/config.js
port: parseInt(process.env.PORT, 10) || 8080,
```

Cloud Run automatically injects `PORT=8080`. No external web server (nginx, Apache) is needed. The worker service also runs a minimal HTTP health server on `PORT` for Cloud Run's health checks (`src/worker.js`).

---

## 8. Concurrency — Scale out via Cloud Run replicas, not threads

Scaling is horizontal via Cloud Run auto-scaling:

```hcl
# modules/cloud-run/main.tf
scaling {
  min_instance_count = 0    # Scale to zero when idle
  max_instance_count = 5    # Scale up under load
}
```

Each instance uses Node.js's single-threaded event loop for concurrent request handling within the instance. Scaling across instances is managed by Cloud Run based on CPU/request metrics. No manual thread management.

---

## 9. Disposability — Fast startup, graceful SIGTERM shutdown, drain in-flight requests

**Fast startup**: Alpine-based Docker images with pre-installed dependencies start in 1-2 seconds. Cloud Run startup probes validate readiness via `/health`.

**Graceful shutdown**: Both services implement proper connection draining (`src/index.js`):

```js
async function shutdown(signal) {
  if (shuttingDown) return;
  shuttingDown = true;
  // Stop accepting new connections, wait for in-flight requests
  await new Promise((resolve) => {
    server.close(() => resolve());
    setTimeout(() => resolve(), 10000); // Force after 10s
  });
  await disconnectRedis();
  process.exit(0);
}
process.on('SIGTERM', () => shutdown('SIGTERM'));
```

Cloud Run sends `SIGTERM` before killing instances. The service:
1. Stops accepting new connections
2. Waits for in-flight requests to complete (up to 10s)
3. Closes Redis connections
4. Exits cleanly

---

## 10. Dev/Prod Parity — Same Docker image runs locally and in production

The exact same Docker image built by CI/CD runs locally and in production. Environment differences are isolated to environment variables only:

```bash
# Run locally with same production image
docker run -p 8080:8080 \
  -e GCP_PROJECT_ID=your-project \
  -e REDIS_HOST=host.docker.internal \
  -e REDIS_PORT=6379 \
  me-central1-docker.pkg.dev/.../movie-service:latest
```

No conditional code paths, no dev-only dependencies in production. The only difference between dev and prod is `pino-pretty` formatting (controlled by `NODE_ENV` in `src/logger.js`).

---

## 11. Logs — Structured JSON logs to stdout, collected by Cloud Logging

All services use **Pino** for structured JSON logging to stdout:

```js
// src/logger.js
const logger = pino({
  level: process.env.LOG_LEVEL || 'info',
});
```

HTTP request logging uses `pino-http` middleware which automatically logs method, URL, status code, and response time for every request.

Output format in production:
```json
{"level":30,"time":1712345678,"msg":"Movie service started","port":8080}
```

Cloud Run captures stdout/stderr and routes all logs to **Cloud Logging** automatically. No file-based logging, no log rotation, no syslog — the app just writes to stdout per 12-factor.

---

## 12. Admin Processes — Seed script runs as a one-off Cloud Run Job, not inside the app

The movie seed script (`src/seed.js`) is a standalone admin process, **not** embedded in the application startup path. It can be executed in two ways:

1. **Cloud Run Job** (production): Provisioned via Terraform (`modules/cloud-run/main.tf` → `google_cloud_run_v2_job.seed_movies`). Uses the same Docker image but overrides the entrypoint to `node src/seed.js`. Run via:
   ```bash
   gcloud run jobs execute seed-movies --region=me-central1
   ```

2. **Standalone script** (development):
   ```bash
   GCP_PROJECT_ID=your-project node src/seed.js
   ```

The seed script checks if the `movies` collection is empty before inserting, making it idempotent and safe to re-run.

---

## 13. API First — All inter-service communication via documented REST APIs

All communication between components uses documented REST APIs:

- **Client ↔ API Gateway**: OpenAPI 2.0 spec (`modules/api-gateway/openapi.yaml.tpl`) defines every endpoint
- **API Gateway ↔ Services**: HTTP routing with `x-google-backend` directives
- **Review Service → Worker**: Pub/Sub messages with typed events (`REVIEW_CREATED`, `REVIEW_DELETED`)

Full API documentation is maintained in `docs/API.md` with method, path, auth requirements, request/response schemas, and examples for every endpoint. Services never share databases or use internal RPC.

---

## 14. Telemetry — Health checks, structured logs, Cloud Monitoring metrics

**Health checks**: Every service exposes `GET /health` returning `{ "status": "ok", "service": "...", "timestamp": "..." }`. Cloud Run uses these for startup and liveness probes:

```hcl
startup_probe {
  http_get { path = "/health" }
  initial_delay_seconds = 5
  period_seconds = 5
  failure_threshold = 3
}
liveness_probe {
  http_get { path = "/health" }
  period_seconds = 30
}
```

**Structured logs**: Pino JSON logs are automatically indexed by Cloud Logging, enabling queries by service, level, request ID, etc.

**Cloud Monitoring**: Cloud Run provides built-in metrics — request count, latency (p50/p95/p99), CPU utilization, memory usage, instance count, and error rate — all available in Cloud Monitoring dashboards with no additional instrumentation.

**Cloud Scheduler**: A nightly job (`modules/scheduler/main.tf`) pings the health endpoint at 2:00 AM Riyadh time, verifying service availability on a schedule.

---

## 15. Auth & Security — Firebase JWT validation, Secret Manager for secrets, least-privilege IAM

**Authentication flow**:
1. Client authenticates via Firebase Auth (Google Sign-In) and receives a JWT
2. API Gateway validates the JWT against Google's public keys (`securityDefinitions.firebase` in OpenAPI spec) before routing
3. Services validate the JWT again via Firebase Admin SDK (`src/middleware/auth.js`) — defense in depth
4. Validated tokens are cached in Redis for 1 hour to avoid redundant Firebase calls

**Secrets management**: All sensitive config stored in Secret Manager (`modules/secret-manager/main.tf`). No plaintext secrets in code, environment, or CI/CD.

**Least-privilege IAM**: Five dedicated service accounts, each with minimal roles (`modules/iam/main.tf`):

| Service Account | Roles |
|----------------|-------|
| `movie-service-sa` | `datastore.user`, `secretmanager.secretAccessor` |
| `review-service-sa` | `datastore.user`, `pubsub.publisher`, `secretmanager.secretAccessor` |
| `review-worker-sa` | `datastore.user`, `pubsub.subscriber`, `secretmanager.secretAccessor` |
| `scheduler-sa` | `run.invoker` |
| `github-actions-sa` | `run.admin`, `artifactregistry.writer`, `iam.serviceAccountUser` |

**Container security**: Docker images run as non-root user (`USER appuser`, UID 1001) defined in each `Dockerfile`.

**CI/CD security**: GitHub Actions authenticates via **Workload Identity Federation** — no service account keys stored in GitHub secrets. The OIDC provider is scoped to `repository_owner=='MaherWasel'` only.
