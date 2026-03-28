# Local Development Guide

Run UniEvent locally before deploying to AWS.

---

## Quick Start (Windows PowerShell)

### 1. Clone the Repository

```powershell
git clone https://github.com/YOUR_USERNAME/Assignment1_AWS_CE.git
cd Assignment1_AWS_CE\app
```

### 2. Create a Virtual Environment

```powershell
python -m venv venv
venv\Scripts\Activate.ps1
```

If you get a red error about execution policy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
venv\Scripts\Activate.ps1
```

### 3. Install Dependencies

```powershell
pip install -r requirements.txt
```

### 4. Set Environment Variables

```powershell
Copy-Item .env.example .env
notepad .env
```

Edit `.env` and add your Ticketmaster API key:

```
FLASK_SECRET_KEY=any-random-string-here
TICKETMASTER_API_KEY=your_actual_key_here
S3_BUCKET_NAME=unievent-local-test
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
```

Save and close Notepad.

For local development, S3 uploads will fail gracefully (the app still runs — it just skips S3 operations). To test S3 locally, install and configure AWS CLI:

```powershell
aws configure
# Enter your Access Key, Secret Key, Region
```

Then set the real bucket name in `.env`.

### 5. Run the Application

```powershell
python app.py
```

The app automatically loads `.env` via python-dotenv — no need to export variables manually.

Open [http://localhost:5000](http://localhost:5000) in your browser.

### 6. Test Endpoints

Open these URLs in your browser:
- http://localhost:5000/ — Homepage with events
- http://localhost:5000/health — Health check JSON
- http://localhost:5000/api/events — Events API JSON
- http://localhost:5000/upload — Upload page (S3 won't work locally)

Or test with PowerShell:
```powershell
# Health check
Invoke-RestMethod http://localhost:5000/health

# Events API
Invoke-RestMethod http://localhost:5000/api/events

# Force refresh
Invoke-RestMethod -Method POST http://localhost:5000/api/refresh
```

---

## Quick Start (macOS / Linux)

```bash
cd Assignment1_AWS_CE/app
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your Ticketmaster API key
python app.py
```

---

## Running with Gunicorn (production mode — Linux/Mac only)

```bash
gunicorn -c gunicorn.conf.py app:app
```

Note: Gunicorn does not run on Windows. For local Windows testing, `python app.py` uses Flask's built-in server which is fine for development.

---

## Project Structure

```
app/
├── app.py              ← Main application (routes, API integration, S3)
├── gunicorn.conf.py    ← Production server config (Linux/EC2 only)
├── requirements.txt    ← Python dependencies
├── .env.example        ← Environment variable template
├── templates/
│   ├── base.html       ← Shared layout (nav, footer)
│   ├── index.html      ← Events grid page
│   ├── event_detail.html ← Single event page
│   └── upload.html     ← Poster upload page
└── static/
    ├── css/style.css   ← All styles
    └── js/main.js      ← Animations and interactions
```

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Python was not found" | Install from https://python.org — check "Add to PATH" during install |
| "running scripts is disabled" | Run: `Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| No events showing | Check your `TICKETMASTER_API_KEY` is set correctly in `app\.env` |
| S3 upload fails | Expected locally without AWS credentials — app still works |
| Port 5000 in use | Close other apps using port 5000, or change port in `app.py` |
| Module not found | Make sure venv is activated: `venv\Scripts\Activate.ps1` |
