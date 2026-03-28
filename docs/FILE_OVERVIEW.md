# UniEvent — Complete File Overview & Deployment Guide

**Student:** Dara | Reg # 2023176 | GIKI — CE 313 Cloud Computing

---

## Part 1: Complete File-by-File Overview

### Root Directory

| # | File | Lines | Purpose | Action Needed? |
|---|------|-------|---------|----------------|
| 1 | `README.md` | 627 | The main assignment deliverable. Contains the full project overview, architecture diagrams (both text-based and SVG image), AWS service justifications for IAM, VPC, EC2, S3, and ELB, the Ticketmaster API selection rationale, complete step-by-step deployment guide (manual console walkthrough in Sections 7.1–7.8), one-click CloudFormation alternative, fault tolerance explanation, and security analysis. The professor reads this first — it is the backbone of the entire submission. | **YES** — Replace `<YOUR_GITHUB_USERNAME>` anywhere it appears. After deployment, add screenshots to Section 12. |
| 2 | `.gitignore` | 12 | Tells Git which files to exclude from the repository. Ignores Python bytecode (`__pycache__/`, `*.pyc`), the `.env` file (so your API keys never get pushed to GitHub), virtual environments (`venv/`), and OS junk files (`.DS_Store`, `Thumbs.db`). This is a safety net — without it, you could accidentally commit your Ticketmaster key to a public repo. | **NO** |
| 3 | `.env.example` | 8 | A template showing the 5 environment variables the application expects. You copy this to `app/.env` and fill in real values. This file IS committed to Git (it contains no secrets, just placeholder text). The actual `.env` file is NOT committed (blocked by `.gitignore`). | **YES** — Copy to `app/.env` and fill in your real Ticketmaster API key and S3 bucket name. |

---

### Application Code — `app/`

These files are the actual web application that runs on the EC2 instances.

| # | File | Lines | Purpose | Action Needed? |
|---|------|-------|---------|----------------|
| 4 | `app/app.py` | 332 | The core Flask application. This single file does everything: (1) On startup, it loads environment variables from a `.env` file using `python-dotenv`, searching three locations — `app/.env`, project root `.env`, and `/opt/unievent/.env` on EC2. (2) It creates an S3 client using `boto3` which authenticates via IAM Instance Profile on EC2 (no hardcoded AWS keys). (3) It starts a background thread that calls the Ticketmaster Discovery API every 30 minutes, processes the JSON response, extracts event titles, dates, venues, descriptions, and images, mirrors images into S3, and stores everything in an in-memory cache. (4) It serves 6 routes: `/` (homepage with event grid), `/event/<id>` (detail page), `/upload` (poster upload to S3), `/api/events` (JSON API), `/api/refresh` (manual re-fetch), and `/health` (ALB health check endpoint that returns `{"status":"healthy"}`). | **NO** — All configuration comes from environment variables. |
| 5 | `app/requirements.txt` | 5 | Lists the 5 Python packages the app depends on: `Flask` (web framework), `gunicorn` (production WSGI server), `boto3` (AWS SDK for S3 operations), `requests` (HTTP client for calling Ticketmaster), and `python-dotenv` (loads `.env` files into `os.environ`). Every deployment script runs `pip install -r requirements.txt` to install these. | **NO** |
| 6 | `app/gunicorn.conf.py` | 10 | Production server configuration. Flask's built-in server cannot handle concurrent requests — Gunicorn spawns 3 worker processes with 2 threads each, all listening on port 5000. The ALB sends traffic to this port. Also configures logging to stdout (captured by systemd journal on EC2) and a 120-second timeout for slow API calls. | **NO** |
| 7 | `app/.env.example` | 18 | Same as the root `.env.example` but with more detailed comments explaining each variable. Includes the URL where you get a free Ticketmaster key. Located here so it is right next to where the `.env` file needs to be created. | **YES** — Copy to `app/.env` and fill in real values (same as root `.env.example`). |
| 8 | `app/templates/base.html` | 58 | The shared HTML layout that every page inherits from using Jinja2 template inheritance (`{% extends "base.html" %}`). Contains the sticky navigation bar (logo + links to Events, Upload, API), a flash message container for success/error notifications, and the footer showing AWS service tags and Ticketmaster attribution. Loads Google Fonts (DM Sans for body text, Playfair Display for headings) and links to the CSS and JS static files. | **NO** |
| 9 | `app/templates/index.html` | 117 | The homepage. Extends `base.html` and adds: a hero section with the title "University Events" and auto-sync status badges, a filter bar with a live search input and category tag buttons (All, Music, Arts, Sports, Education — populated dynamically from the events data), a refresh button that calls `/api/refresh` via JavaScript fetch, and a responsive CSS Grid of event cards. Each card shows the event image, category badge, title, date/time, venue, description preview (truncated to 150 chars), and a "View Details" button. If no events are cached, shows an empty state with a "Fetch Events Now" button. | **NO** |
| 10 | `app/templates/event_detail.html` | 76 | Single event detail page. Shows a full-width hero banner with the event image as a blurred background, the event title, and category badge. Below that, a two-column layout: the left column has the full description and image, the right sidebar shows date, time, venue, city, category in a structured list, a "Register / Get Tickets" button linking to the Ticketmaster page, and an infrastructure card explaining which AWS services serve this page (a nice touch for the assignment). | **NO** |
| 11 | `app/templates/upload.html` | 107 | The poster upload page. Features a drag-and-drop zone with visual feedback (border changes on drag-over), a file input that accepts PNG, JPG, GIF, and WebP, an image preview with filename and size before uploading, and a submit button that sends the file to S3 via a hidden HTML form. After successful upload, displays the S3 URL with a copy-to-clipboard button. All interactivity is handled by inline JavaScript — no external dependencies. | **NO** |
| 12 | `app/static/css/style.css` | 443 | The complete stylesheet. Defines a dark theme (background `#0e0f11`, text `#e4e4e7`, amber accent `#f59e0b`) using CSS custom properties for consistency. Styles every component: navbar with `backdrop-filter: blur`, hero section with a radial gradient glow, event card grid with hover animations (translateY + scale on image), detail page two-column layout, upload drag-and-drop box, flash messages, filter tags with active state, and responsive breakpoints for mobile (single-column grid below 640px). | **NO** |
| 13 | `app/static/js/main.js` | 32 | Client-side JavaScript that adds a scroll-triggered fade-in animation to event cards using IntersectionObserver. When a card scrolls into the viewport, it transitions from `opacity: 0; translateY(20px)` to fully visible with a staggered delay. Purely cosmetic — the app works without it. | **NO** |

---

### Infrastructure — `infrastructure/`

| # | File | Lines | Purpose | Action Needed? |
|---|------|-------|---------|----------------|
| 14 | `infrastructure/cloudformation.yaml` | 473 | A single AWS CloudFormation template that creates the ENTIRE infrastructure stack in one command. Defines 20+ AWS resources: VPC (10.0.0.0/16) with DNS enabled, 2 public subnets and 2 private subnets across two Availability Zones, Internet Gateway attached to the VPC, NAT Gateway with an Elastic IP in Public Subnet 1, public and private route tables with correct routes, 3 security groups (ALB allows 80/443 from internet, EC2 allows 5000 from ALB only, Bastion allows SSH), IAM Role with least-privilege S3 policy and SSM access, Instance Profile attached to the role, S3 Bucket with public-read policies for `event-images/` and `event-posters/` prefixes and CORS configuration, Application Load Balancer in public subnets, Target Group with `/health` health checks on port 5000, HTTP listener forwarding to the target group, 2 EC2 instances in private subnets each writing a `.env` file and creating a systemd service, and a Bastion Host in the public subnet. Takes 4 parameters: TicketmasterApiKey, KeyPairName, InstanceType, and AmiId. | **YES** — Replace `<YOUR_GITHUB_USERNAME>` in both EC2 UserData blocks. Then deploy using the CloudFormation command in the README. |

---

### Scripts — `scripts/`

| # | File | Lines | Purpose | Action Needed? |
|---|------|-------|---------|----------------|
| 15 | `scripts/ec2-user-data.sh` | 61 | The EC2 bootstrap script. Runs automatically at first boot when pasted into the "User Data" field during manual EC2 launch via the AWS Console. It does 5 things in order: (1) installs Python 3, pip, and Git, (2) clones the GitHub repository to `/opt/unievent`, (3) installs Python dependencies from `requirements.txt`, (4) writes the 5 environment variables to `/opt/unievent/.env`, (5) creates a systemd service called `unievent` that loads the `.env` file via `EnvironmentFile`, runs Gunicorn, and auto-restarts on crash. This is the script used when deploying manually through the AWS Console (README Section 7.6). | **YES** — Replace `<YOUR_GITHUB_USERNAME>`, your Ticketmaster key, and your S3 bucket name before pasting into EC2 User Data. |
| 16 | `scripts/deploy-aws-cli.sh` | 265 | An automated deployment script that creates everything using AWS CLI commands. It is the manual console steps from README Sections 7.2–7.7 translated into a single runnable bash script. Creates VPC, 4 subnets, IGW, NAT Gateway, route tables, security groups, IAM role + instance profile, S3 bucket with policy, 2 EC2 instances (each with a `.env` file and systemd service created via UserData), target group, ALB, and listener. Outputs the final ALB URL at the end. Takes about 5 minutes to complete (most of the wait is the NAT Gateway becoming available). | **YES** — Edit the 4 configuration variables at the top of the file: `REGION`, `KEY_PAIR`, `TICKETMASTER_KEY`, and `GITHUB_REPO`. Then run with `bash scripts/deploy-aws-cli.sh`. |
| 17 | `scripts/cleanup.sh` | 102 | Tears down every AWS resource to avoid ongoing charges. Deletes in reverse dependency order: ALB listeners → ALB → Target Group → EC2 instances (waits for termination) → S3 bucket (force-empties first) → NAT Gateway (waits 60s for deletion) → Elastic IPs → Security Groups → Subnets → Route Tables → Internet Gateway → VPC → IAM resources. Asks for confirmation before proceeding. Run this when the assignment is graded and you want to stop all charges. | **YES** — Run `bash scripts/cleanup.sh` when you are completely done. |
| 18 | `scripts/local-setup.sh` | 77 | Sets up a local development environment on your own laptop. Checks for Python 3, creates a virtual environment in `app/venv/`, installs dependencies, creates a `.env` file from the template if one doesn't exist, and optionally starts the Flask dev server on `localhost:5000`. Useful for testing the UI and API integration before spending money on AWS resources. Note: S3 uploads will fail locally unless you run `aws configure` first with valid credentials. | **YES** — Run `bash scripts/local-setup.sh` as your first step to test the app locally. |

---

### Documentation — `docs/`

| # | File | Lines | Purpose | Action Needed? |
|---|------|-------|---------|----------------|
| 19 | `docs/architecture-diagram.svg` | 103 | A dark-themed SVG vector diagram showing the complete AWS architecture. Renders directly on GitHub when referenced in the README via `![](docs/architecture-diagram.svg)`. Shows Internet Users → ALB (in both public subnets) → EC2 instances (in both private subnets) → S3 and Ticketmaster API, with color-coded subnets (green=public, purple=private), labeled security groups, IAM roles, NAT Gateway, IGW, and Bastion Host. | **NO** |
| 20 | `docs/preview.html` | 359 | A standalone HTML file that renders a fully interactive preview of the UniEvent web app using mock event data and Unsplash placeholder images. Open in any browser — no server or AWS needed. Shows the exact UI: dark theme, event card grid with hover animations, search bar, category filters, status bar showing health/instance count. Useful for demonstrating to the professor what the deployed app looks like without needing the infrastructure running. | **NO** — Just open in a browser. |
| 21 | `docs/API.md` | 135 | REST API documentation for all 6 endpoints. For each endpoint, shows the HTTP method, path, description, request parameters, and example JSON response. Includes the data flow diagram (Ticketmaster → Flask → S3 / Memory Cache → JSON or HTML), rate limit information (5,000 Ticketmaster requests/day, 48 fetches/day at 30-min intervals), and authentication notes (IAM for S3, API key for Ticketmaster). | **NO** |
| 22 | `docs/API_JUSTIFICATION.md` | 161 | Detailed justification for choosing the Ticketmaster Discovery API over alternatives. Compares Ticketmaster vs Eventbrite vs PredictHQ vs SeatGeek across 8 criteria: structured JSON, event fields (title, date, venue, description, images), free tier limits, documentation quality, reliability, authentication complexity, image availability, and geographic coverage. Includes a sample API request with query parameters and a mapped response showing how each JSON field translates to the app's data model. This fulfills the assignment requirement that "students must independently discover, evaluate, and justify the API they choose." | **NO** |
| 23 | `docs/TESTING.md` | 202 | A verification checklist with 8 tests and exact CLI commands to prove every assignment requirement is met. Test 1: App accessible via ALB. Test 2: Health check returns healthy. Test 3: Events fetched from Ticketmaster. Test 4: Images mirrored to S3. Test 5: Poster upload to S3. Test 6: Fault tolerance — stop one EC2 instance, verify site stays up, restart and verify it rejoins. Test 7: EC2 not directly accessible from internet. Test 8: IAM role used, no hardcoded credentials. Each test has a pass/fail criteria and a checkbox. Run these after deployment and screenshot the results. | **YES** — Follow these tests after deployment and capture screenshots for the submission. |
| 24 | `docs/LOCAL_DEVELOPMENT.md` | 116 | Guide for running the app on your local machine. Covers prerequisites (Python 3.8+, pip, AWS CLI optional), environment setup, creating the `.env` file, running with Flask dev server vs Gunicorn, testing API endpoints with curl, and common issues (S3 failures without AWS credentials, Ticketmaster rate limits). | **NO** |

---

## Part 2: How Credentials Flow

Every file that needs secrets reads them the same way:

```
                    ┌─────────────────────────────────┐
                    │       .env file is created       │
                    │   (by user locally, or by the    │
                    │   deployment script on EC2)      │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │    systemd loads .env via        │
                    │    EnvironmentFile directive     │
                    │    (on EC2 only)                 │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │    python-dotenv also loads      │
                    │    .env as a fallback            │
                    │    (works both locally & EC2)    │
                    └────────────────┬────────────────┘
                                     │
                    ┌────────────────▼────────────────┐
                    │    app.py reads os.environ.get() │
                    │    for all 5 variables            │
                    └──────────────────────────────────┘
```

The 5 environment variables used everywhere:

| Variable | What It Is | Where It Goes |
|----------|-----------|---------------|
| `FLASK_SECRET_KEY` | Random string for session encryption | Flask's `app.secret_key` |
| `TICKETMASTER_API_KEY` | Your free API key from developer.ticketmaster.com | Passed as `?apikey=` in every Ticketmaster request |
| `S3_BUCKET_NAME` | Your S3 bucket name (e.g., `unievent-media-123456`) | Used by boto3 for all S3 uploads and URL generation |
| `AWS_REGION` | AWS region (e.g., `us-east-1`) | S3 client initialization and URL construction |
| `FETCH_INTERVAL` | Seconds between API fetches (default: 1800 = 30 min) | Background thread sleep duration |

---

## Part 3: The Three Deployment Methods (Compared)

### Method A: Manual AWS Console (README Section 7)

**What you do:** Click through the AWS Console step by step — create VPC, subnets, IGW, NAT, route tables, security groups, IAM role, S3 bucket, EC2 instances, ALB, and target group. Paste `scripts/ec2-user-data.sh` into the EC2 User Data field.

| Pros | Cons |
|------|------|
| Best for learning — you see every resource being created | Takes 30–45 minutes of clicking |
| Easy to screenshot each step for the assignment | Easy to miss a step or misconfigure something |
| Matches what the professor likely expects | Hard to reproduce exactly if something breaks |

**Best for:** Assignments where you need to show screenshots of every AWS Console step.

---

### Method B: AWS CLI Script (`scripts/deploy-aws-cli.sh`)

**What you do:** Edit 4 variables at the top of the script, then run `bash scripts/deploy-aws-cli.sh`. It creates everything automatically and prints the ALB URL at the end.

| Pros | Cons |
|------|------|
| 5 minutes instead of 45 | Requires AWS CLI installed and configured |
| Reproducible — run again to recreate | Harder to screenshot individual steps |
| Good for testing before manual deployment | Less "hand-on" learning |
| Outputs all resource IDs for easy cleanup | |

**Best for:** Testing the deployment works before doing it manually, or if you need to redeploy quickly after cleanup.

---

### Method C: CloudFormation (`infrastructure/cloudformation.yaml`)

**What you do:** Run one command:
```bash
aws cloudformation create-stack \
  --stack-name UniEvent \
  --template-body file://infrastructure/cloudformation.yaml \
  --parameters \
    ParameterKey=TicketmasterApiKey,ParameterValue=YOUR_KEY \
    ParameterKey=KeyPairName,ParameterValue=YOUR_KEYPAIR \
  --capabilities CAPABILITY_NAMED_IAM
```

| Pros | Cons |
|------|------|
| True Infrastructure-as-Code — one file defines everything | Debugging failures is harder (check CloudFormation events) |
| Atomic — if any resource fails, the entire stack rolls back | Cannot screenshot individual console steps |
| Industry best practice | Requires understanding of CloudFormation syntax |
| Easy cleanup: `aws cloudformation delete-stack --stack-name UniEvent` | |

**Best for:** Professional deployments and demonstrating cloud architecture expertise.

---

### Recommended Approach for This Assignment

Use **Method B (CLI Script) first** to verify everything works, then do **Method A (Manual Console)** to take the screenshots the professor needs. Here is the exact workflow:

**Step 1 — Test locally first (5 minutes)**
```bash
bash scripts/local-setup.sh
```
Open `http://localhost:5000` and verify events load and the UI looks correct. Fix any issues before touching AWS.

**Step 2 — Deploy with CLI script to verify (10 minutes)**
```bash
# Edit the 4 config variables at the top first
bash scripts/deploy-aws-cli.sh
```
Visit the ALB URL it prints. Run the tests from `docs/TESTING.md`. If something is wrong, run `bash scripts/cleanup.sh` and fix it.

**Step 3 — Clean up the CLI deployment**
```bash
bash scripts/cleanup.sh
```

**Step 4 — Deploy manually via Console and screenshot everything (30–45 minutes)**
Follow README Section 7 step by step. At each stage, take a screenshot:
- VPC with 4 subnets
- Route tables with correct routes
- Security groups with correct rules
- IAM role with S3 policy
- S3 bucket with bucket policy
- Both EC2 instances running in private subnets
- ALB with healthy target group
- Homepage showing events
- Event detail page
- Upload page with a successful S3 upload
- `/health` endpoint response
- Fault tolerance test — stop one instance, site still works

**Step 5 — Run TESTING.md tests and screenshot results**
```bash
# Follow each test in docs/TESTING.md
```

**Step 6 — Add screenshots to README Section 12 and push to GitHub**

**Step 7 — Clean up when graded**
```bash
bash scripts/cleanup.sh
```

---

## Part 4: Quick-Start Summary (Actions Only)

| Step | What To Do | Files Involved |
|------|-----------|----------------|
| 1 | Get a free Ticketmaster API key from developer.ticketmaster.com | — |
| 2 | Create an EC2 Key Pair in the AWS Console | — |
| 3 | Copy `.env.example` → `app/.env` and fill in your API key and bucket name | `.env.example`, `app/.env` |
| 4 | Replace `<YOUR_GITHUB_USERNAME>` in deployment files | `scripts/ec2-user-data.sh`, `infrastructure/cloudformation.yaml` |
| 5 | Test locally: `bash scripts/local-setup.sh` | `scripts/local-setup.sh` |
| 6 | Deploy to AWS (CLI or Console) | `scripts/deploy-aws-cli.sh` or `README.md` Section 7 |
| 7 | Run verification tests | `docs/TESTING.md` |
| 8 | Add screenshots to README and push to GitHub | `README.md` |
| 9 | Clean up AWS resources when done | `scripts/cleanup.sh` |
