# Movies Review App — REST API Documentation

Base URL: `https://<API_GATEWAY_HOST>`

All endpoints (except `/health`) require a Firebase Auth JWT in the `Authorization: Bearer <token>` header.

---

## Movie Service

### List All Movies
- **Method:** `GET`
- **Path:** `/movies`
- **Auth:** Required
- **Request Body:** None
- **Response:**
```json
{
  "movies": [
    {
      "id": "abc123",
      "title": "The Shawshank Redemption",
      "year": 1994,
      "genre": ["Drama"],
      "director": "Frank Darabont",
      "plot": "Two imprisoned men bond...",
      "posterUrl": "https://...",
      "rating": 4.5,
      "reviewCount": 10,
      "likeCount": 25,
      "dislikeCount": 2,
      "createdAt": "2025-01-01T00:00:00.000Z",
      "updatedAt": "2025-01-15T00:00:00.000Z"
    }
  ]
}
```

### Get Single Movie
- **Method:** `GET`
- **Path:** `/movies/:id`
- **Auth:** Required
- **Response:**
```json
{
  "id": "abc123",
  "title": "The Shawshank Redemption",
  "year": 1994,
  "genre": ["Drama"],
  "director": "Frank Darabont",
  "plot": "Two imprisoned men bond...",
  "posterUrl": "https://...",
  "rating": 4.5,
  "reviewCount": 10,
  "likeCount": 25,
  "dislikeCount": 2
}
```
- **404:** `{ "error": "Movie not found" }`

---

## Review Service

### List Reviews for a Movie
- **Method:** `GET`
- **Path:** `/reviews?movieId=<movieId>`
- **Auth:** Required
- **Query Params:** `movieId` (required)
- **Response:**
```json
{
  "reviews": [
    {
      "id": "rev123",
      "movieId": "abc123",
      "userId": "uid_xyz",
      "userName": "John Doe",
      "text": "Amazing movie!",
      "rating": 5,
      "createdAt": "2025-01-10T12:00:00.000Z"
    }
  ]
}
```

### Add a Review
- **Method:** `POST`
- **Path:** `/reviews`
- **Auth:** Required
- **Request Body:**
```json
{
  "movieId": "abc123",
  "text": "Great movie, loved it!",
  "rating": 5
}
```
- **Validation:** `rating` must be 1-5, all fields required
- **Response (201):**
```json
{
  "id": "rev456",
  "movieId": "abc123",
  "userId": "uid_xyz",
  "userName": "John Doe",
  "text": "Great movie, loved it!",
  "rating": 5,
  "createdAt": "2025-01-10T12:00:00.000Z"
}
```
- **Side effect:** Publishes `REVIEW_CREATED` event to Pub/Sub

### Delete Own Review
- **Method:** `DELETE`
- **Path:** `/reviews/:id`
- **Auth:** Required (must own the review)
- **Response:**
```json
{ "message": "Review deleted" }
```
- **403:** `{ "error": "You can only delete your own reviews" }`
- **404:** `{ "error": "Review not found" }`
- **Side effect:** Publishes `REVIEW_DELETED` event to Pub/Sub

### Like a Movie
- **Method:** `POST`
- **Path:** `/movies/:id/like`
- **Auth:** Required
- **Request Body:** None
- **Response (201):** `{ "message": "Movie liked" }`
- **Response (200):** `{ "message": "Switched to like" }` (was dislike)
- **409:** `{ "error": "Already liked this movie" }`

### Dislike a Movie
- **Method:** `POST`
- **Path:** `/movies/:id/dislike`
- **Auth:** Required
- **Request Body:** None
- **Response (201):** `{ "message": "Movie disliked" }`
- **Response (200):** `{ "message": "Switched to dislike" }` (was like)
- **409:** `{ "error": "Already disliked this movie" }`

---

## Health Check
- **Method:** `GET`
- **Path:** `/health`
- **Auth:** Not required
- **Response:**
```json
{
  "status": "ok",
  "service": "movie-service",
  "timestamp": "2025-01-10T12:00:00.000Z"
}
```

---

## Error Responses

All errors follow this format:
```json
{ "error": "Description of the error" }
```

| Status | Meaning |
|--------|---------|
| 400 | Bad request / validation error |
| 401 | Missing or invalid auth token |
| 403 | Forbidden (not resource owner) |
| 404 | Resource not found |
| 409 | Conflict (duplicate action) |
| 500 | Internal server error |
