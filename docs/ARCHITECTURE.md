# System Architecture

## High-Level Overview

```
                    ┌─────────────┐
                    │  Client App │  (React SPA)
                    │  Firebase   │  Google Sign-In → JWT
                    └──────┬──────┘
                           │ HTTPS + Bearer JWT
                    ┌──────▼──────┐
                    │ API Gateway │  (europe-west1)
                    │ JWT Validate│  OpenAPI 2.0 spec
                    └──┬──────┬───┘
              ┌────────▼┐  ┌─▼────────┐
              │  Movie  │  │  Review  │
              │ Service │  │ Service  │  (Cloud Run, me-central1)
              └────┬────┘  └──┬───┬───┘
                   │          │   │ Pub/Sub publish
              ┌────▼──────────▼┐  │
              │   Firestore    │  ├───────────────┐
              │  (us-central1) │  │               │
              └────────────────┘  │   ┌───────────▼───────┐
                                  │   │ review-events topic│
              ┌────────────────┐  │   └───────────┬───────┘
              │  Memorystore   │  │               │
              │  Redis 7.0     │◄─┘   ┌───────────▼───────┐
              │  (me-central1) │      │ review-events-sub  │
              └────────────────┘      └───────────┬───────┘
                                                  │
                                      ┌───────────▼───────┐
                                      │   Review Worker   │
                                      │   (Cloud Run)     │
                                      │   Rating recalc   │
                                      └───────────────────┘
```

## Components

### Client Layer
- **React SPA** (`movies-frontend`) — Authenticates via Firebase Auth (Google Sign-In), receives a JWT, sends it with every API request as `Authorization: Bearer <token>`.

### API Gateway Layer
- **Cloud API Gateway** (europe-west1) — Single entry point for all API traffic. Validates Firebase JWTs using Google's public keys before routing requests. Defined via OpenAPI 2.0 spec with `x-google-backend` extensions pointing to Cloud Run services.

### Service Layer

| Service | Runtime | Purpose |
|---------|---------|---------|
| **Movie Service** | Cloud Run (me-central1) | Movie listing and retrieval. Reads from Firestore `movies` collection. |
| **Review Service** | Cloud Run (me-central1) | Review CRUD, like/dislike operations. Publishes events to Pub/Sub. |
| **Review Worker** | Cloud Run (me-central1, min 1 instance) | Subscribes to Pub/Sub. Recalculates movie aggregate ratings asynchronously. |
| **Seed Job** | Cloud Run Job | One-off admin process to seed initial movie data into Firestore. |

All services validate JWT tokens via Firebase Admin SDK with Redis caching (defense in depth — API Gateway validates first).

### Data Layer

**Firestore** (us-central1) — Primary database with three collections:

| Collection | Key Schema | Purpose |
|-----------|------------|---------|
| `movies` | Auto-generated ID | Movie data + aggregate fields (rating, reviewCount, likeCount, dislikeCount) |
| `reviews` | Auto-generated ID | User reviews linked to movies via `movieId` field |
| `likes` | `{userId}_{movieId}` | Like/dislike records. Composite key enforces one vote per user per movie. |

**Memorystore Redis 7.0** (me-central1) — Caches validated Firebase JWT tokens. Key format: `token:<last-16-chars-of-JWT>`. TTL: 1 hour. Prevents redundant Firebase token verification on repeated requests. Cache miss falls back gracefully to Firebase Admin SDK.

### Messaging Layer

**Cloud Pub/Sub**:
- Topic: `review-events`
- Subscription: `review-events-sub` (pull-based)
- Events: `REVIEW_CREATED`, `REVIEW_DELETED`
- Retry policy: exponential backoff, 10s–600s
- No expiration

When a review is created or deleted, the Review Service publishes an event. The Worker consumes it and recalculates the movie's average rating asynchronously, decoupling the write path from the aggregation logic.

### Scheduling Layer

**Cloud Scheduler** — Nightly job at 2:00 AM (Asia/Riyadh) that pings the Movie Service health endpoint. Verifies service availability and can be extended for periodic maintenance tasks. Authenticates via OIDC with a dedicated service account.

### CI/CD Pipeline

**GitHub Actions** (per service repo):
1. Triggered on push to `main`
2. Authenticates to GCP via **Workload Identity Federation** (keyless — no service account keys)
3. Builds Docker image and tags with git SHA + `latest`
4. Pushes to **Artifact Registry** (`movies-docker` repository)
5. Updates Cloud Run service with new image

**Artifact Registry** (me-central1) — Single Docker repository `movies-docker` stores all service images.

### Security & IAM

**Secret Manager** — Stores 5 secrets:
- `firebase-project-id`
- `redis-host`, `redis-port`
- `pubsub-topic`, `pubsub-subscription`

All injected into Cloud Run containers at runtime via `value_source.secret_key_ref`.

**Service Accounts** — One per service, least-privilege:

| Account | Roles |
|---------|-------|
| `movie-service-sa` | Firestore user, Secret Manager accessor |
| `review-service-sa` | Firestore user, Pub/Sub publisher, Secret Manager accessor |
| `review-worker-sa` | Firestore user, Pub/Sub subscriber, Secret Manager accessor |
| `scheduler-sa` | Cloud Run invoker |
| `github-actions-sa` | Cloud Run admin, Artifact Registry writer, SA user |

**Workload Identity Federation** — GitHub Actions authenticates via OIDC tokens. Pool scoped to `repository_owner=='MaherWasel'` only.

## Data Flows

### Read Flow (Get Movies)
```
Client → API Gateway (JWT validation) → Movie Service → Firestore → Response
```

### Write Flow (Add Review)
```
Client → API Gateway (JWT validation) → Review Service
  ├── Firestore (write review)
  └── Pub/Sub (publish REVIEW_CREATED)
        └── Worker → Firestore (recalculate movie rating)
```

### Auth Flow
```
Client → Firebase Auth (Google Sign-In) → JWT issued
Client → API Gateway (JWT validated against Google public keys)
       → Cloud Run service (JWT validated against Redis cache or Firebase Admin SDK)
       → Redis (cache validated token for 1 hour)
```

### Like/Dislike Flow
```
Client → API Gateway → Review Service → Firestore Transaction:
  1. Check existing like doc ({userId}_{movieId})
  2. Create/update like record
  3. Update movie likeCount/dislikeCount atomically
```

## Network Architecture

- Cloud Run services connect to Memorystore Redis via a **VPC Connector** (`movies-vpc-connector`, CIDR `10.8.0.0/28`).
- Redis is on the default VPC network — **not publicly accessible**.
- Cloud Run services accept public traffic but JWT validation is enforced at two layers (API Gateway + service middleware) — defense in depth.
- API Gateway is deployed in `europe-west1` (closest supported region); services are in `me-central1`.
