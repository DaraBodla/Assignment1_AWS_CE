"""
UniEvent - University Event Management System
Flask application that fetches events from Ticketmaster Discovery API
and displays them as university events. Images stored in AWS S3.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Load .env from the app directory or project root (local dev & EC2 systemd)
# On EC2 the systemd service uses EnvironmentFile, but this is a safe fallback.
_env_paths = [
    Path(__file__).resolve().parent / ".env",          # app/.env
    Path(__file__).resolve().parent.parent / ".env",   # project root .env
    Path("/opt/unievent/.env"),                        # EC2 deployment path
]
for _p in _env_paths:
    if _p.is_file():
        load_dotenv(_p)
        break

import json
import time
import logging
import hashlib
import requests
import boto3
from datetime import datetime, timedelta
from threading import Thread
from flask import Flask, render_template, jsonify, request, redirect, url_for, flash
from werkzeug.utils import secure_filename
from botocore.exceptions import ClientError

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
app = Flask(__name__)
app.secret_key = os.environ.get("FLASK_SECRET_KEY", "unievent-secret-key-change-in-prod")

# Ticketmaster Discovery API (free tier – 5 000 req/day)
TICKETMASTER_API_KEY = os.environ.get("TICKETMASTER_API_KEY", "YOUR_API_KEY_HERE")
TICKETMASTER_BASE    = "https://app.ticketmaster.com/discovery/v2"

# AWS S3
S3_BUCKET   = os.environ.get("S3_BUCKET_NAME", "unievent-media-bucket")
AWS_REGION  = os.environ.get("AWS_REGION", "us-east-1")

# Fetch interval (seconds) – default 30 min
FETCH_INTERVAL = int(os.environ.get("FETCH_INTERVAL", 1800))

# Allowed upload extensions
ALLOWED_EXTENSIONS = {"png", "jpg", "jpeg", "gif", "webp"}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# AWS clients (uses IAM Instance Profile when running on EC2)
# ---------------------------------------------------------------------------
try:
    s3_client = boto3.client("s3", region_name=AWS_REGION)
    logger.info("S3 client initialised for region %s", AWS_REGION)
except Exception as exc:
    logger.warning("Could not create S3 client: %s", exc)
    s3_client = None

# ---------------------------------------------------------------------------
# In-memory event cache (shared across requests)
# ---------------------------------------------------------------------------
events_cache: list[dict] = []
last_fetch_time: str = "Never"


# ---------------------------------------------------------------------------
# Helper utilities
# ---------------------------------------------------------------------------
def allowed_file(filename: str) -> bool:
    return "." in filename and filename.rsplit(".", 1)[1].lower() in ALLOWED_EXTENSIONS


def upload_to_s3(file_obj, filename: str) -> str | None:
    """Upload a file object to S3 and return its public URL."""
    if s3_client is None:
        logger.error("S3 client not available")
        return None
    try:
        key = f"event-posters/{filename}"
        s3_client.upload_fileobj(
            file_obj,
            S3_BUCKET,
            key,
            ExtraArgs={"ContentType": file_obj.content_type},
        )
        url = f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{key}"
        logger.info("Uploaded %s to S3", key)
        return url
    except ClientError as exc:
        logger.error("S3 upload failed: %s", exc)
        return None


def download_image_to_s3(image_url: str) -> str | None:
    """Download a remote image and mirror it into S3."""
    if s3_client is None or not image_url:
        return image_url  # fall back to original URL
    try:
        resp = requests.get(image_url, timeout=10)
        resp.raise_for_status()
        url_hash = hashlib.md5(image_url.encode()).hexdigest()
        ext = image_url.rsplit(".", 1)[-1].split("?")[0][:4] or "jpg"
        key = f"event-images/{url_hash}.{ext}"
        s3_client.put_object(
            Bucket=S3_BUCKET,
            Key=key,
            Body=resp.content,
            ContentType=resp.headers.get("Content-Type", "image/jpeg"),
        )
        return f"https://{S3_BUCKET}.s3.{AWS_REGION}.amazonaws.com/{key}"
    except Exception as exc:
        logger.warning("Image mirror failed (%s): %s", image_url, exc)
        return image_url


# ---------------------------------------------------------------------------
# Ticketmaster API integration
# ---------------------------------------------------------------------------
def fetch_events_from_api() -> list[dict]:
    """Fetch upcoming events from Ticketmaster Discovery API."""
    global events_cache, last_fetch_time

    logger.info("Fetching events from Ticketmaster …")
    params = {
        "apikey": TICKETMASTER_API_KEY,
        "size": 20,
        "sort": "date,asc",
        "startDateTime": datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%SZ"),
        "endDateTime": (datetime.utcnow() + timedelta(days=90)).strftime(
            "%Y-%m-%dT%H:%M:%SZ"
        ),
        "classificationName": "Music,Arts,Sports,Education,Festival",
        "countryCode": "US",
    }

    try:
        resp = requests.get(
            f"{TICKETMASTER_BASE}/events.json", params=params, timeout=15
        )
        resp.raise_for_status()
        data = resp.json()

        raw_events = data.get("_embedded", {}).get("events", [])
        processed: list[dict] = []

        for ev in raw_events:
            # Extract best image
            images = ev.get("images", [])
            image_url = ""
            if images:
                # prefer 16:9 ratio, largest width
                best = sorted(
                    images, key=lambda i: i.get("width", 0), reverse=True
                )
                image_url = best[0].get("url", "")

            # Mirror image to S3
            s3_image = download_image_to_s3(image_url)

            # Extract venue
            venues = (
                ev.get("_embedded", {}).get("venues", [{}])
            )
            venue_name = venues[0].get("name", "TBA") if venues else "TBA"
            venue_city = (
                venues[0].get("city", {}).get("name", "") if venues else ""
            )

            # Extract date
            dates = ev.get("dates", {}).get("start", {})
            event_date = dates.get("localDate", "TBA")
            event_time = dates.get("localTime", "")

            processed.append(
                {
                    "id": ev.get("id", ""),
                    "title": ev.get("name", "Untitled Event"),
                    "description": (
                        ev.get("info")
                        or ev.get("pleaseNote")
                        or f"Join us for {ev.get('name', 'this exciting event')} "
                        f"at {venue_name}!"
                    ),
                    "date": event_date,
                    "time": event_time,
                    "venue": venue_name,
                    "city": venue_city,
                    "image_url": s3_image or image_url,
                    "ticket_url": ev.get("url", "#"),
                    "category": (
                        ev.get("classifications", [{}])[0]
                        .get("segment", {})
                        .get("name", "General")
                        if ev.get("classifications")
                        else "General"
                    ),
                }
            )

        events_cache = processed
        last_fetch_time = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC")
        logger.info("Fetched and cached %d events", len(processed))
        return processed

    except requests.RequestException as exc:
        logger.error("Ticketmaster API error: %s", exc)
        return events_cache  # return stale cache on failure


# ---------------------------------------------------------------------------
# Background scheduler (simple thread-based)
# ---------------------------------------------------------------------------
def background_fetcher():
    """Periodically fetch events in a background thread."""
    while True:
        try:
            fetch_events_from_api()
        except Exception as exc:
            logger.error("Background fetch error: %s", exc)
        time.sleep(FETCH_INTERVAL)


# ---------------------------------------------------------------------------
# Flask routes
# ---------------------------------------------------------------------------
@app.route("/")
def index():
    """Landing page – list all university events."""
    if not events_cache:
        fetch_events_from_api()
    return render_template(
        "index.html", events=events_cache, last_fetch=last_fetch_time
    )


@app.route("/event/<event_id>")
def event_detail(event_id: str):
    """Single event detail page."""
    event = next((e for e in events_cache if e["id"] == event_id), None)
    if event is None:
        flash("Event not found.", "error")
        return redirect(url_for("index"))
    return render_template("event_detail.html", event=event)


@app.route("/upload", methods=["GET", "POST"])
def upload_poster():
    """Upload an event poster to S3."""
    if request.method == "POST":
        if "poster" not in request.files:
            flash("No file selected.", "error")
            return redirect(request.url)

        file = request.files["poster"]
        if file.filename == "":
            flash("No file selected.", "error")
            return redirect(request.url)

        if file and allowed_file(file.filename):
            filename = secure_filename(file.filename)
            ts = datetime.utcnow().strftime("%Y%m%d%H%M%S")
            filename = f"{ts}_{filename}"
            url = upload_to_s3(file, filename)
            if url:
                flash(f"Poster uploaded successfully!", "success")
                return render_template("upload.html", uploaded_url=url)
            else:
                flash("Upload failed – check S3 configuration.", "error")
        else:
            flash("File type not allowed. Use PNG, JPG, GIF, or WebP.", "error")

    return render_template("upload.html", uploaded_url=None)


@app.route("/api/events")
def api_events():
    """REST endpoint – return cached events as JSON."""
    return jsonify(
        {
            "status": "ok",
            "count": len(events_cache),
            "last_fetch": last_fetch_time,
            "events": events_cache,
        }
    )


@app.route("/api/refresh", methods=["POST"])
def api_refresh():
    """Manually trigger a refresh from Ticketmaster."""
    events = fetch_events_from_api()
    return jsonify({"status": "ok", "count": len(events)})


@app.route("/health")
def health():
    """Health-check endpoint used by the ALB target group."""
    return jsonify(
        {
            "status": "healthy",
            "timestamp": datetime.utcnow().isoformat(),
            "cached_events": len(events_cache),
        }
    )


# ---------------------------------------------------------------------------
# Application entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    # Kick off initial fetch
    fetch_events_from_api()
    # Start background fetcher thread
    fetcher = Thread(target=background_fetcher, daemon=True)
    fetcher.start()
    # Run Flask (Gunicorn in production)
    app.run(host="0.0.0.0", port=5000, debug=False)
