# System Architecture

## Components

### Client Layer
- **Mobile/Web App** — Authenticates via Firebase Auth (Google Sign-In), receives a JWT, sends it with every API request.

### API Gateway Layer
- **Cloud API Gateway** — Single entry point for all API traffic. Validates Firebase JWTs using Google's public keys before routing requests. Defined via OpenAPI 2.0 spec with `x-google-backend` extensions pointing to Cloud Run services.

### Service Layer
- **Movie Service** (Cloud Run) — Handles movie listing and retrieval. Seeds Firestore with initial movie data on startup if empty. Validates cached tokens via Redis middleware.
- **Review Service** (Cloud Run) — Handles review CRUD and like/dislike operations. Publishes `REVIEW_CREATED` and `REVIEW_DELETED` events to Pub/Sub on mutations.
- **Review Worker** (Cloud Run) — Subscribes to the `review-events-sub` Pub/Sub subscription. Recalculates movie aggregate ratings asynchronously when reviews are added or deleted.

### Data Layer
- **Firestore** — Primary database with three collections:
  - `movies` — Pre-seeded movie data with aggregate fields (rating, reviewCount, likeCount, dislikeCount)
  - `reviews` — User-submitted reviews linked to movies
  - `likes` — Like/dislike records keyed as `{userId}_{movieId}` to enforce uniqueness
- **Memorystore (Redis)** — Caches validated Firebase JWT tokens. Key format: `token:<last-16-chars>`. TTL: 1 hour. Prevents redundant Firebase token verification on repeated requests.

### Messaging Layer
- **Cloud Pub/Sub** — Topic: `review-events`. Subscription: `review-events-sub`. Carries review lifecycle events for async processing (rating aggregation). Retry policy with exponential backoff (10s–600s).

### Scheduling Layer
- **Cloud Scheduler** — Runs a nightly job (2:00 AM Riyadh time) that hits the Movie Service health endpoint. Verifies service availability and can be extended for seed validation or rating re-aggregation.

### CI/CD Pipeline
- **Cloud Build** — Two triggers (one per service repo) fire on push to `main`. Each trigger: builds Docker image → pushes to Artifact Registry → deploys to Cloud Run. No manual steps.
- **Artifact Registry** — Single Docker repository (`movies-docker`) stores all service images tagged with commit SHA and `latest`.

### Security & IAM
- **Secret Manager** — Stores Firebase project ID and Redis connection details. Referenced by service accounts.
- **Service Accounts** — One per service, each with least-privilege roles:
  - `movie-service-sa`: Firestore read/write, Secret Manager access
  - `review-service-sa`: Firestore read/write, Pub/Sub publisher, Secret Manager access
  - `review-worker-sa`: Firestore read/write, Pub/Sub subscriber
  - `scheduler-sa`: Cloud Run invoker
  - `cloud-build-sa`: Cloud Run admin, Artifact Registry writer

## Data Flow

### Read Flow (Get Movies)
```
Client → API Gateway (JWT validation) → Movie Service → Firestore → Response
```

### Write Flow (Add Review)
```
Client → API Gateway (JWT validation) → Review Service → Firestore (write review)
                                                        → Pub/Sub (publish event)
                                                              ↓
                                                        Review Worker → Firestore (recalculate rating)
```

### Auth Flow
```
Client → Firebase Auth (Google Sign-In) → JWT issued
Client → API Gateway (JWT validated against Google public keys)
       → Cloud Run (JWT validated against Redis cache or Firebase Admin SDK)
       → Redis (cache validated token for 1 hour)
```

### Like/Dislike Flow
```
Client → API Gateway → Review Service → Firestore Transaction:
                                          1. Check existing like doc
                                          2. Create/update like record
                                          3. Update movie counters atomically
```

## Network Architecture
- Cloud Run services connect to Memorystore Redis via a **VPC Connector** (`movies-vpc-connector`, CIDR `10.8.0.0/28`).
- Redis is on the default VPC network, not publicly accessible.
- Cloud Run services accept public traffic but JWT validation is enforced at the API Gateway level and again at the service level (defense in depth).
