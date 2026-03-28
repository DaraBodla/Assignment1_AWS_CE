#!/bin/bash
# ===========================================================================
# UniEvent — Local Development Setup
# Run this on your local machine to test the app before AWS deployment.
# ===========================================================================
set -euo pipefail

echo "╔══════════════════════════════════════════╗"
echo "║   UniEvent — Local Development Setup     ║"
echo "╚══════════════════════════════════════════╝"

# Check Python
if ! command -v python3 &>/dev/null; then
    echo "❌ Python 3 is required. Install it first."
    exit 1
fi
echo "✓ Python 3 found: $(python3 --version)"

# Navigate to app directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$SCRIPT_DIR/../app"
cd "$APP_DIR"

# Create virtual environment
if [ ! -d "venv" ]; then
    echo "→ Creating virtual environment…"
    python3 -m venv venv
fi

echo "→ Activating virtual environment…"
source venv/bin/activate

echo "→ Installing dependencies…"
pip install -r requirements.txt --quiet

# Check for .env
if [ ! -f ".env" ]; then
    echo ""
    echo "⚠  No .env file found. Creating from .env.example…"
    if [ -f ".env.example" ]; then
        cp .env.example .env
        echo "   Edit app/.env with your Ticketmaster API key before running."
    else
        cat > .env <<'EOF'
FLASK_SECRET_KEY=local-dev-secret
TICKETMASTER_API_KEY=YOUR_KEY_HERE
S3_BUCKET_NAME=unievent-local-test
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
EOF
        echo "   Edit app/.env with your Ticketmaster API key before running."
    fi
fi

# Load environment
set -a; source .env; set +a

echo ""
echo "✓ Setup complete!"
echo ""
echo "  To run the app:"
echo "    cd app && source venv/bin/activate"
echo "    python app.py"
echo ""
echo "  Then open http://localhost:5000 in your browser."
echo ""
echo "  Note: S3 uploads won't work locally unless you have"
echo "  AWS credentials configured (aws configure)."
echo ""

# Ask to run
read -p "Start the server now? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "→ Starting UniEvent on http://localhost:5000 …"
    python app.py
fi
