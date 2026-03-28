# UniEvent — API Documentation

## Base URL

```
http://<ALB-DNS-NAME>
```

---

## Endpoints

### 1. Health Check

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/health` | Returns system health status. Used by ALB target group for health checks. |

**Response (200 OK):**
```json
{
  "status": "healthy",
  "timestamp": "2026-03-25T14:30:00.000000",
  "cached_events": 20
}
```

---

### 2. List Events (Web)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/` | Returns the HTML events listing page |

Renders all cached events with search/filter capabilities.

---

### 3. Event Detail (Web)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/event/<event_id>` | Returns the HTML detail page for a single event |

**Parameters:**
- `event_id` (path) — Ticketmaster event ID string

---

### 4. List Events (JSON API)

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/api/events` | Returns all cached events as JSON |

**Response (200 OK):**
```json
{
  "status": "ok",
  "count": 20,
  "last_fetch": "2026-03-25 14:30:00 UTC",
  "events": [
    {
      "id": "vvG1IZ9YLkLfRB",
      "title": "Spring Music Festival",
      "description": "Annual spring music celebration ...",
      "date": "2026-04-15",
      "time": "18:00:00",
      "venue": "University Grand Arena",
      "city": "New York",
      "image_url": "https://unievent-media-123456.s3.us-east-1.amazonaws.com/event-images/abc123.jpg",
      "ticket_url": "https://www.ticketmaster.com/event/...",
      "category": "Music"
    }
  ]
}
```

---

### 5. Refresh Events

| Method | Path | Description |
|--------|------|-------------|
| `POST` | `/api/refresh` | Triggers an immediate re-fetch from Ticketmaster API |

**Response (200 OK):**
```json
{
  "status": "ok",
  "count": 20
}
```

---

### 6. Upload Poster

| Method | Path | Description |
|--------|------|-------------|
| `GET` | `/upload` | Returns the upload form page |
| `POST` | `/upload` | Uploads a poster image to S3 |

**POST Parameters:**
- `poster` (file) — Image file (PNG, JPG, GIF, or WebP)

**On success:** Renders upload page with S3 URL of the uploaded file.

---

## Data Flow

```
Ticketmaster API  ──(HTTPS GET)──>  Flask App  ──(boto3)──>  S3 Bucket
                                       │
                                       ▼
                                  In-memory cache
                                       │
                                       ▼
                                  /api/events  ──>  JSON response
                                  /            ──>  HTML page
```

## Rate Limits

- Ticketmaster free tier: **5,000 requests/day**
- Default fetch interval: every **30 minutes** (48 fetches/day)
- Manual refresh: no built-in rate limit (use responsibly)

## Authentication

- No authentication required for reading events
- S3 uploads are authorized via the EC2 IAM Instance Profile
- Ticketmaster API uses an API key passed as a query parameter
