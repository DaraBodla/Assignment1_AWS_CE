# UniEvent — Testing & Verification Guide

This document outlines the tests to perform after deployment to verify that the UniEvent system meets all assignment requirements.

> **Windows users:** The commands below use `curl` and `bash` syntax. You can run most tests simply by opening the URLs in your browser instead. For tests that need CLI, use PowerShell with `Invoke-RestMethod` (shown as alternatives where relevant), or use the AWS Console directly.

---

## Test 1: Application Availability

**Objective:** Confirm the app is accessible via the ALB endpoint.

**Browser method:** Go to EC2 → Load Balancers → copy the DNS name → open `http://DNS_NAME` in your browser. If the page loads, this test passes.

**CLI method (bash/Linux):**
```bash
# Get ALB DNS name
ALB_DNS=$(aws elbv2 describe-load-balancers --names UniEvent-ALB \
    --query 'LoadBalancers[0].DNSName' --output text)

# Test the homepage
curl -s -o /dev/null -w "%{http_code}" http://$ALB_DNS/
# Expected: 200
```

**Pass criteria:** HTTP 200 response with HTML content.

---

## Test 2: Health Check Endpoint

**Objective:** Verify ALB health check path is working.

```bash
curl -s http://$ALB_DNS/health | python3 -m json.tool
```

**Expected output:**
```json
{
    "status": "healthy",
    "timestamp": "2026-03-25T...",
    "cached_events": 20
}
```

**Pass criteria:** `status` is `"healthy"`, `cached_events` > 0.

---

## Test 3: Event Data Fetching (Ticketmaster API)

**Objective:** Confirm events are fetched from external API.

```bash
curl -s http://$ALB_DNS/api/events | python3 -m json.tool | head -20
```

**Pass criteria:**
- `status` is `"ok"`
- `count` > 0
- Each event has: `title`, `date`, `venue`, `description`, `image_url`

---

## Test 4: S3 Image Mirroring

**Objective:** Verify event images are stored in S3.

```bash
# Check S3 bucket for mirrored images
BUCKET="unievent-media-$(aws sts get-caller-identity --query Account --output text)"
aws s3 ls s3://$BUCKET/event-images/ --summarize
```

**Pass criteria:** At least one image file exists in `event-images/` prefix.

---

## Test 5: Poster Upload to S3

**Objective:** Test the file upload functionality.

```bash
# Create a test image
convert -size 200x200 xc:blue /tmp/test-poster.jpg 2>/dev/null || \
    echo "test" > /tmp/test-poster.jpg

# Upload via the API
curl -X POST http://$ALB_DNS/upload \
    -F "poster=@/tmp/test-poster.jpg" \
    -s -o /dev/null -w "%{http_code}"
# Expected: 200
```

**Or test manually:**
1. Open `http://<ALB_DNS>/upload` in browser
2. Drag and drop an image
3. Click "Upload to S3"
4. Verify the S3 URL is displayed

**Pass criteria:** File appears in `s3://<bucket>/event-posters/`.

---

## Test 6: Fault Tolerance (Critical Test)

**Objective:** Prove the system continues operating when one EC2 instance fails.

### Step-by-step:

```bash
# 1. Verify both instances are healthy
aws elbv2 describe-target-health --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[].{ID:Target.Id,Health:TargetHealth.State}'
# Expected: both "healthy"

# 2. Record the homepage response
curl -s http://$ALB_DNS/ > /tmp/before.html
echo "Before: $(wc -c < /tmp/before.html) bytes"

# 3. Stop one EC2 instance
EC2_1=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=UniEvent-App-1" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
aws ec2 stop-instances --instance-ids $EC2_1
echo "Stopped: $EC2_1"

# 4. Wait for ALB to detect unhealthy (90 seconds)
echo "Waiting 90 seconds for health check to fail..."
sleep 90

# 5. Verify target health (one healthy, one unhealthy)
aws elbv2 describe-target-health --target-group-arn $TG_ARN \
    --query 'TargetHealthDescriptions[].{ID:Target.Id,Health:TargetHealth.State}'
# Expected: one "healthy", one "unhealthy" or "unused"

# 6. Test the site STILL WORKS
curl -s http://$ALB_DNS/ > /tmp/after.html
echo "After: $(wc -c < /tmp/after.html) bytes"
curl -s http://$ALB_DNS/health
# Expected: still returns healthy JSON

# 7. Restart the stopped instance
aws ec2 start-instances --instance-ids $EC2_1
echo "Restarted: $EC2_1 — will rejoin ALB in ~2 minutes"
```

**Pass criteria:**
- Site remains accessible after stopping one instance
- ALB correctly routes all traffic to the remaining healthy instance
- After restart, both instances return to "healthy" state

---

## Test 7: Security Verification

**Objective:** Confirm EC2 instances are not directly accessible from the internet.

```bash
# Try to reach EC2 directly (should fail/timeout)
EC2_PRIVATE_IP=$(aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=UniEvent-App-1" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
echo "Private IP: $EC2_PRIVATE_IP"

# This should timeout (instance has no public IP)
curl --connect-timeout 5 http://$EC2_PRIVATE_IP:5000/health 2>&1 || echo "EXPECTED: Connection refused/timeout"
```

**Pass criteria:** Direct connection fails; only ALB can reach port 5000.

---

## Test 8: IAM Role Verification

**Objective:** Confirm EC2 uses IAM Instance Profile (no hard-coded credentials).

```bash
# SSH via bastion → check EC2 metadata
ssh -J ec2-user@<BASTION_IP> ec2-user@<EC2_PRIVATE_IP>

# On the EC2 instance:
curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/
# Expected: "UniEvent-EC2-Role"

# Verify no .aws/credentials file
ls ~/.aws/credentials 2>&1
# Expected: "No such file or directory"
```

**Pass criteria:** Instance uses role-based credentials, no static keys.

---

## Test Summary Checklist

| # | Test | Requirement Validated | Status |
|---|------|----------------------|--------|
| 1 | App accessible via ALB | Multi-AZ deployment | ☐ |
| 2 | Health check works | ALB health monitoring | ☐ |
| 3 | Events fetched from API | External API integration | ☐ |
| 4 | Images mirrored to S3 | S3 storage for images | ☐ |
| 5 | Poster upload works | S3 upload functionality | ☐ |
| 6 | Fault tolerance | System survives instance failure | ☐ |
| 7 | EC2 not publicly accessible | Private subnet security | ☐ |
| 8 | IAM role (no hard-coded keys) | Security best practices | ☐ |
