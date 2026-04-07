swagger: "2.0"
info:
  title: Movies Review API
  version: "1.0.0"
host: ""
schemes:
  - https
produces:
  - application/json

securityDefinitions:
  firebase:
    authorizationUrl: ""
    flow: "implicit"
    type: "oauth2"
    x-google-issuer: "https://securetoken.google.com/${firebase_project_id}"
    x-google-jwks_uri: "https://www.googleapis.com/service_accounts/v1/metadata/x509/securetoken@system.gserviceaccount.com"
    x-google-audiences: "${firebase_project_id}"

paths:
  /movies:
    get:
      summary: List all movies
      operationId: listMovies
      security:
        - firebase: []
      x-google-backend:
        address: ${movie_service_url}/movies
      responses:
        200:
          description: OK

  /movies/{movieId}:
    get:
      summary: Get a single movie
      operationId: getMovie
      security:
        - firebase: []
      parameters:
        - name: movieId
          in: path
          required: true
          type: string
      x-google-backend:
        address: ${movie_service_url}/movies
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        200:
          description: OK

  /movies/{movieId}/like:
    post:
      summary: Like a movie
      operationId: likeMovie
      security:
        - firebase: []
      parameters:
        - name: movieId
          in: path
          required: true
          type: string
      x-google-backend:
        address: ${review_service_url}/movies
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        201:
          description: Created

  /movies/{movieId}/dislike:
    post:
      summary: Dislike a movie
      operationId: dislikeMovie
      security:
        - firebase: []
      parameters:
        - name: movieId
          in: path
          required: true
          type: string
      x-google-backend:
        address: ${review_service_url}/movies
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        201:
          description: Created

  /reviews:
    get:
      summary: List reviews for a movie
      operationId: listReviews
      security:
        - firebase: []
      parameters:
        - name: movieId
          in: query
          required: true
          type: string
      x-google-backend:
        address: ${review_service_url}/reviews
      responses:
        200:
          description: OK
    post:
      summary: Add a review
      operationId: addReview
      security:
        - firebase: []
      x-google-backend:
        address: ${review_service_url}/reviews
      responses:
        201:
          description: Created

  /reviews/{reviewId}:
    delete:
      summary: Delete own review
      operationId: deleteReview
      security:
        - firebase: []
      parameters:
        - name: reviewId
          in: path
          required: true
          type: string
      x-google-backend:
        address: ${review_service_url}/reviews
        path_translation: APPEND_PATH_TO_ADDRESS
      responses:
        200:
          description: OK

  /health:
    get:
      summary: Health check
      operationId: healthCheck
      x-google-backend:
        address: ${movie_service_url}/health
      responses:
        200:
          description: OK
