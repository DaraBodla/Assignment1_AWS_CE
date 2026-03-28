#!/bin/bash
# ===========================================================================
# UniEvent — EC2 User-Data Bootstrap Script
# Run at instance launch to install dependencies & start the application.
# ===========================================================================
set -euo pipefail

LOG="/var/log/unievent-setup.log"
exec > >(tee -a "$LOG") 2>&1
echo "=== UniEvent bootstrap started at $(date) ==="

# ---------- 1. System packages ----------
yum update -y
yum install -y python3 python3-pip git

# ---------- 2. Clone application ----------
APP_DIR="/opt/unievent"
rm -rf "$APP_DIR"
git clone https://github.com/DaraBodla/Assignment1_AWS_CE.git "$APP_DIR"
cd "$APP_DIR/app"

# ---------- 3. Python dependencies ----------
pip3 install --upgrade pip
pip3 install -r requirements.txt

# ---------- 4. Environment variables ----------
# Replace placeholder values before deploying or use SSM Parameter Store
cat > /opt/unievent/.env <<'ENVEOF'
FLASK_SECRET_KEY=replace-with-a-strong-random-string
TICKETMASTER_API_KEY=47y8AsP4ZjXIkYGX3eLLzRDwvcN9haJW
S3_BUCKET_NAME=unievent-media-bucket
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
ENVEOF

set -a; source /opt/unievent/.env; set +a

# ---------- 5. Systemd service ----------
cat > /etc/systemd/system/unievent.service <<'SVCEOF'
[Unit]
Description=UniEvent Flask Application
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/unievent/app
EnvironmentFile=/opt/unievent/.env
ExecStart=/usr/local/bin/gunicorn -c gunicorn.conf.py app:app
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable unievent
systemctl start unievent

echo "=== UniEvent bootstrap completed at $(date) ==="
