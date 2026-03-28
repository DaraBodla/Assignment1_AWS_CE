# API Evaluation & Justification

## Requirement

The UniEvent system must automatically fetch event data from an external Open API. The selected API must provide structured JSON data including: event title, date, venue, description, and optionally event images.

---

## APIs Evaluated

### 1. Ticketmaster Discovery API v2 (SELECTED)

| Attribute | Details |
|-----------|---------|
| **URL** | `https://app.ticketmaster.com/discovery/v2/events.json` |
| **Auth** | API key as query parameter (`?apikey=...`) |
| **Free Tier** | 5,000 requests/day |
| **Rate Limit** | 5 req/sec |
| **Docs** | https://developer.ticketmaster.com/products-and-docs/apis/discovery-api/v2/ |

**Data fields available:**
- `name` → Event title
- `dates.start.localDate` → Event date
- `dates.start.localTime` → Event time
- `_embedded.venues[0].name` → Venue name
- `_embedded.venues[0].city.name` → City
- `info` / `pleaseNote` → Description
- `images[]` → Multiple images in various sizes/ratios
- `classifications[].segment.name` → Category (Music, Sports, Arts, etc.)
- `url` → Ticketmaster event page (for registration)

**Strengths:**
- Simple API key auth (no OAuth complexity)
- Rich, well-structured JSON responses
- Multiple high-quality images per event
- Filterable by classification, date range, location, keyword
- Production-grade reliability (Live Nation infrastructure)
- Excellent documentation with interactive API explorer

**Limitations:**
- US/EU-focused events primarily
- API key required (free but needs registration)

---

### 2. Eventbrite API (Rejected)

| Attribute | Details |
|-----------|---------|
| **Auth** | OAuth 2.0 (token-based) |
| **Free Tier** | Yes, but limited |

**Reason for rejection:**
- Requires OAuth 2.0 flow, adding significant complexity for a demo
- User must authorize access to their Eventbrite account
- Not truly "open" — requires an Eventbrite account context
- Private events may not be accessible without organizer permissions
- API has been increasingly restricted in recent years

---

### 3. PredictHQ API (Rejected)

| Attribute | Details |
|-----------|---------|
| **Auth** | API key (Bearer token) |
| **Free Tier** | Very limited (no images) |

**Reason for rejection:**
- Free tier extremely restrictive
- Does not provide event images
- Focused on event intelligence/analytics rather than consumer-facing data
- Overkill for our use case

---

### 4. Open Events / Meetup API (Rejected)

**Reason for rejection:**
- Meetup API requires OAuth and Pro subscription for most endpoints
- Open Events databases often have stale or incomplete data
- No guaranteed image availability

---

## Decision Matrix

| Criterion (weight) | Ticketmaster | Eventbrite | PredictHQ |
|---------------------|:-----------:|:----------:|:---------:|
| Simple Auth (25%) | 5 | 2 | 4 |
| Image Availability (20%) | 5 | 4 | 1 |
| Data Completeness (20%) | 5 | 4 | 3 |
| Free Tier Generosity (15%) | 5 | 3 | 2 |
| Documentation Quality (10%) | 5 | 4 | 3 |
| Reliability (10%) | 5 | 4 | 4 |
| **Weighted Score** | **5.00** | **3.35** | **2.65** |

---

## Conclusion

**Ticketmaster Discovery API v2** is the optimal choice for UniEvent because it combines simple authentication, comprehensive event data with high-quality images, a generous free tier, and production-grade reliability. Its straightforward API key authentication eliminates OAuth complexity while providing richer data than alternatives.

---

## Sample API Call

```bash
curl "https://app.ticketmaster.com/discovery/v2/events.json?\
apikey=YOUR_KEY&\
size=5&\
sort=date,asc&\
classificationName=Music&\
countryCode=US" | python3 -m json.tool
```

## Sample Response (truncated)

```json
{
  "_embedded": {
    "events": [
      {
        "name": "Spring Music Festival 2026",
        "id": "vvG1IZ9YLkLfRB",
        "url": "https://www.ticketmaster.com/event/...",
        "dates": {
          "start": {
            "localDate": "2026-04-15",
            "localTime": "19:00:00"
          }
        },
        "info": "Join us for an evening of live music...",
        "images": [
          {
            "url": "https://s1.ticketm.net/dam/a/123/image.jpg",
            "width": 1024,
            "height": 576,
            "ratio": "16_9"
          }
        ],
        "classifications": [
          {
            "segment": { "name": "Music" },
            "genre": { "name": "Rock" }
          }
        ],
        "_embedded": {
          "venues": [
            {
              "name": "University Arena",
              "city": { "name": "Austin" },
              "state": { "name": "Texas" }
            }
          ]
        }
      }
    ]
  }
}
```
