# UniEvent — Complete AWS Deployment Guide (Beginner Friendly)

**For:** Dara | GIKI | CE 313 Cloud Computing
**Goal:** Deploy UniEvent on AWS without getting charged

---

## COST OVERVIEW — READ THIS FIRST

AWS Free Tier gives you 12 months of free resources after account creation. Here is exactly what this project uses and whether it costs money:

| Resource | Free Tier Allowance | What We Use | Will You Be Charged? |
|----------|-------------------|-------------|---------------------|
| EC2 (t2.micro) | 750 hrs/month | 2 instances = ~1,440 hrs/month | **YES — you get 750 free hours total, but 2 instances burn through it in ~15 days. SHUT THEM DOWN after screenshots.** |
| S3 | 5 GB storage, 20,000 GET requests | A few MB of images | **NO** — well within limits |
| ALB | NOT in free tier | 1 load balancer | **YES — ~$0.60/day ($18/month). DELETE IMMEDIATELY after demo.** |
| NAT Gateway | NOT in free tier | 1 NAT gateway | **YES — ~$1.08/day ($32/month). DELETE IMMEDIATELY after demo.** |
| Elastic IP | Free while attached to a running instance | 1 (for NAT) | **YES if instance is stopped** |
| VPC, Subnets, IGW, SGs, IAM | Always free | Used | **NO** |
| Data Transfer | 100 GB/month outbound free | Minimal | **NO** |

### THE GOLDEN RULE

> **Deploy → Take screenshots → Run tests → DELETE EVERYTHING within 2-3 hours.**
> Total cost for a 3-hour session: approximately $0.15 to $0.25.
> If you forget to delete and leave it running for a month: approximately $55.

---

## PHASE 0: Prerequisites (One-Time Setup)

### Step 0.1 — Create an AWS Account

1. Go to https://aws.amazon.com/ and click **Create an AWS Account**
2. Enter your email, set a password, choose an account name
3. Enter your credit/debit card (required even for free tier — you won't be charged if you clean up)
4. Choose the **Basic Support (Free)** plan
5. Wait for account activation (can take a few minutes to a few hours)

**Important:** If you already have a GIKI lab AWS account or AWS Educate account, use that instead — it may have free credits.

### Step 0.2 — Get a Ticketmaster API Key (Free)

1. Go to https://developer.ticketmaster.com/
2. Click **Get Your API Key** → Create an account (use any email)
3. After login, go to **My Apps** in the top menu
4. You will see a default app already created
5. Copy the **Consumer Key** — this is your API key (looks like: `AbCd1234EfGh5678`)
6. Save it somewhere — you will need it later

### Step 0.3 — Install AWS CLI on Your Laptop (Windows)

1. Download from https://awscli.amazonaws.com/AWSCLIV2.msi
2. Run the installer, click Next through everything
3. Close and reopen PowerShell

Verify it works:
```powershell
aws --version
```
Should print: `aws-cli/2.x.x ...`

### Step 0.4 — Configure AWS CLI with Your Credentials

1. Go to the AWS Console → Click your name (top right) → **Security Credentials**
2. Scroll to **Access Keys** → **Create access key**
3. Choose **Command Line Interface (CLI)** → Check the confirmation → **Create**
4. **COPY BOTH KEYS NOW** — you will not see the secret key again

Now run in PowerShell:
```powershell
aws configure
```
Enter:
- **AWS Access Key ID:** (paste the access key)
- **AWS Secret Access Key:** (paste the secret key)
- **Default region name:** `us-east-1`
- **Default output format:** `json`

### Step 0.5 — Create a Key Pair (for SSH access to EC2)

1. Go to AWS Console → **EC2** → Left sidebar: **Key Pairs**
2. Click **Create key pair**
3. Name: `unievent-key`
4. Key pair type: **RSA**
5. File format: `.ppk` (for Windows — select `.pem` only if you use WSL)
6. Click **Create key pair** — it downloads automatically
7. **Save this file** somewhere safe — you cannot re-download it

### Step 0.6 — Push the Code to GitHub

First, install Git if you don't have it: https://git-scm.com/download/win (use the default settings in the installer).

Then in PowerShell:
```powershell
cd C:\Users\darab\OneDrive\Desktop\cloud_assignment\Assignment1_AWS_CE
git init
git add .
git commit -m "UniEvent: AWS Cloud Architecture Assignment"
git branch -M main
git remote add origin https://github.com/YOUR_USERNAME/Assignment1_AWS_CE.git
git push -u origin main
```

Replace `YOUR_USERNAME` with your actual GitHub username. If asked to login, enter your GitHub credentials or personal access token.

---

## PHASE 1: Test Locally First (5 minutes, costs $0)

Before touching AWS, verify the app works on your laptop.

### Step 1.1 — Make Sure Python Is Installed

Open PowerShell and run:
```powershell
python --version
```

If it says "Python was not found", install Python:
1. Go to https://www.python.org/downloads/
2. Download the latest Python 3.12 or 3.13
3. Run the installer — **CHECK THE BOX "Add Python to PATH"** (this is critical)
4. Click "Install Now"
5. Close and reopen PowerShell, then try `python --version` again

### Step 1.2 — Create the .env File

```powershell
cd C:\Users\darab\OneDrive\Desktop\cloud_assignment\Assignment1_AWS_CE
Copy-Item .env.example app\.env
```

Now open `app\.env` in Notepad and replace only the API key line:
```powershell
notepad app\.env
```

Change it to:
```
FLASK_SECRET_KEY=any-random-string-here-for-local-testing
TICKETMASTER_API_KEY=YOUR_ACTUAL_TICKETMASTER_KEY_HERE
S3_BUCKET_NAME=unievent-local-test
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
```

Save and close Notepad.

### Step 1.3 — Install Dependencies and Run

```powershell
cd app
python -m venv venv
venv\Scripts\Activate.ps1
pip install -r requirements.txt
python app.py
```

**If you get a red error about "running scripts is disabled"**, run this first:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```
Then try `venv\Scripts\Activate.ps1` again.

### Step 1.4 — Verify

Open your browser to http://localhost:5000

You should see:
- The dark-themed UniEvent homepage
- Event cards with images from Ticketmaster
- Search and filter working
- The `/health` endpoint at http://localhost:5000/health returning JSON

**Upload will NOT work locally** (no S3 bucket yet) — that is expected.

Press Ctrl+C in PowerShell to stop the server.

---

## PHASE 2: Deploy on AWS — Manual Console Method

This is the method that gives you screenshots for the assignment. Follow every step exactly.

### Step 2.1 — Create the VPC

1. Go to AWS Console → search **VPC** → click **VPC**
2. Click **Create VPC**
3. Choose **VPC only** (not "VPC and more")
4. Settings:
   - **Name tag:** `UniEvent-VPC`
   - **IPv4 CIDR block:** `10.0.0.0/16`
   - Leave everything else as default
5. Click **Create VPC**
6. **📸 SCREENSHOT: The VPC details page showing the VPC ID and CIDR**

Now enable DNS hostnames:
1. Select your VPC → **Actions** → **Edit VPC settings**
2. Check **Enable DNS hostnames**
3. Click **Save**

### Step 2.2 — Create 4 Subnets

Go to **VPC** → Left sidebar: **Subnets** → **Create subnet**

Select VPC: `UniEvent-VPC`

**Create all 4 subnets one by one** (click "Add new subnet" to add more in the same screen):

| Subnet Name | CIDR Block | Availability Zone | Purpose |
|-------------|-----------|-------------------|---------|
| `UniEvent-Public-1` | `10.0.1.0/24` | us-east-1a | ALB + NAT |
| `UniEvent-Public-2` | `10.0.2.0/24` | us-east-1b | ALB |
| `UniEvent-Private-1` | `10.0.10.0/24` | us-east-1a | EC2 App #1 |
| `UniEvent-Private-2` | `10.0.20.0/24` | us-east-1b | EC2 App #2 |

Click **Create subnet**.

Now enable auto-assign public IP on the two PUBLIC subnets only:
1. Select `UniEvent-Public-1` → **Actions** → **Edit subnet settings**
2. Check **Enable auto-assign public IPv4 address** → **Save**
3. Repeat for `UniEvent-Public-2`

**📸 SCREENSHOT: Subnets list showing all 4 subnets**

### Step 2.3 — Create and Attach Internet Gateway

1. **VPC** → Left sidebar: **Internet Gateways** → **Create internet gateway**
2. Name: `UniEvent-IGW`
3. Click **Create internet gateway**
4. The page will show the new IGW. Click **Actions** → **Attach to VPC**
5. Select `UniEvent-VPC` → Click **Attach internet gateway**

**📸 SCREENSHOT: Internet Gateway showing "Attached" state**

### Step 2.4 — Create NAT Gateway

⚠️ **THIS COSTS MONEY — ~$1.08/day. Delete it as soon as you finish.**

1. **VPC** → Left sidebar: **NAT Gateways** → **Create NAT gateway**
2. Settings:
   - **Name:** `UniEvent-NAT`
   - **Subnet:** `UniEvent-Public-1` (must be a PUBLIC subnet)
   - **Connectivity type:** Public
   - Click **Allocate Elastic IP** (a new IP will appear)
3. Click **Create NAT gateway**
4. Wait 1-2 minutes until status changes from "Pending" to **"Available"**

**📸 SCREENSHOT: NAT Gateway showing "Available" status**

### Step 2.5 — Create Route Tables

**Public Route Table:**

1. **VPC** → **Route Tables** → **Create route table**
2. Name: `UniEvent-Public-RT`, VPC: `UniEvent-VPC` → **Create**
3. Select it → **Routes** tab → **Edit routes** → **Add route**:
   - Destination: `0.0.0.0/0`
   - Target: Select **Internet Gateway** → select `UniEvent-IGW`
4. Click **Save changes**
5. Go to **Subnet associations** tab → **Edit subnet associations**
6. Check `UniEvent-Public-1` and `UniEvent-Public-2` → **Save associations**

**Private Route Table:**

1. Create another route table: Name: `UniEvent-Private-RT`, VPC: `UniEvent-VPC`
2. **Routes** tab → **Edit routes** → **Add route**:
   - Destination: `0.0.0.0/0`
   - Target: Select **NAT Gateway** → select `UniEvent-NAT`
3. **Save changes**
4. **Subnet associations** → Check `UniEvent-Private-1` and `UniEvent-Private-2` → **Save**

**📸 SCREENSHOT: Both route tables showing their routes**

### Step 2.6 — Create Security Groups

Go to **VPC** → **Security Groups** → **Create security group**

**Security Group 1: ALB**

| Field | Value |
|-------|-------|
| Name | `UniEvent-ALB-SG` |
| Description | `Allow HTTP to ALB` |
| VPC | `UniEvent-VPC` |
| Inbound Rule 1 | Type: **HTTP**, Source: **Anywhere-IPv4** (0.0.0.0/0) |
| Inbound Rule 2 | Type: **HTTPS**, Source: **Anywhere-IPv4** (0.0.0.0/0) |

Click **Create security group**.

**Security Group 2: EC2**

| Field | Value |
|-------|-------|
| Name | `UniEvent-EC2-SG` |
| Description | `Allow traffic from ALB only` |
| VPC | `UniEvent-VPC` |
| Inbound Rule 1 | Type: **Custom TCP**, Port: **5000**, Source: select **UniEvent-ALB-SG** (start typing the name) |
| Inbound Rule 2 | Type: **SSH**, Port: **22**, Source: **Anywhere-IPv4** (for debugging; restrict to your IP in production) |

Click **Create security group**.

**📸 SCREENSHOT: Both security groups with their inbound rules**

### Step 2.7 — Create IAM Role for EC2

1. Go to **IAM** (search for it in the top bar) → Left sidebar: **Roles** → **Create role**
2. **Trusted entity type:** AWS service
3. **Use case:** EC2
4. Click **Next**
5. Search for and check: `AmazonSSMManagedInstanceCore`
6. Click **Next**
7. **Role name:** `UniEvent-EC2-Role`
8. Click **Create role**

Now add the S3 policy:
1. Click on the role you just created → **Add permissions** → **Create inline policy**
2. Click the **JSON** tab and paste:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:ListBucket",
        "s3:DeleteObject"
      ],
      "Resource": [
        "arn:aws:s3:::unievent-media-*",
        "arn:aws:s3:::unievent-media-*/*"
      ]
    }
  ]
}
```

3. Click **Next** → Policy name: `UniEvent-S3-Access` → **Create policy**

**📸 SCREENSHOT: IAM Role showing both attached policies**

### Step 2.8 — Create the S3 Bucket

This is how you "get a bucket":

1. Go to **S3** (search for it) → **Create bucket**
2. Settings:
   - **Bucket name:** `unievent-media-` followed by your AWS account ID or any unique suffix
     - Example: `unievent-media-dara2023` (must be globally unique across all AWS accounts)
   - **Region:** US East (N. Virginia) us-east-1
   - **Object Ownership:** ACLs disabled (recommended)
3. **Uncheck** "Block all public access"
   - A warning appears — check the acknowledgement box
4. Leave everything else as default
5. Click **Create bucket**

**📸 SCREENSHOT: S3 bucket created**

**IMPORTANT: Remember your bucket name — you need it in the next steps.**

Now add the bucket policy for public image access:
1. Click on your bucket → **Permissions** tab → **Bucket policy** → **Edit**
2. Paste this (replace `YOUR-BUCKET-NAME` with your actual bucket name):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadImages",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/event-images/*"
    },
    {
      "Sid": "PublicReadPosters",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/event-posters/*"
    }
  ]
}
```

3. Click **Save changes**

**📸 SCREENSHOT: Bucket policy saved**

### Step 2.9 — Launch EC2 Instance #1

⚠️ **t2.micro is free tier eligible (750 hours/month). But with 2 instances, you use 1,440 hours — you will go over free tier after ~15 days. Shut down within hours.**

1. Go to **EC2** → **Launch Instances**
2. Settings:
   - **Name:** `UniEvent-App-1`
   - **AMI:** Amazon Linux 2023 (should be the default, free tier eligible — look for the "Free tier eligible" badge)
   - **Instance type:** `t2.micro` (Free tier eligible)
   - **Key pair:** `unievent-key` (the one you created in Step 0.5)
3. **Network settings** → Click **Edit**:
   - **VPC:** `UniEvent-VPC`
   - **Subnet:** `UniEvent-Private-1`
   - **Auto-assign public IP:** Disable
   - **Security group:** Select existing → `UniEvent-EC2-SG`
4. **Advanced details** (scroll down and expand):
   - **IAM instance profile:** `UniEvent-EC2-Role`
   - **User data:** Scroll to the very bottom — there is a text box. Paste the following:

```bash
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y python3 python3-pip git

git clone https://github.com/YOUR_GITHUB_USERNAME/Assignment1_AWS_CE.git /opt/unievent
cd /opt/unievent/app
pip3 install -r requirements.txt

cat > /opt/unievent/.env <<'EOF'
FLASK_SECRET_KEY=prod-secret-change-this-to-random-text
TICKETMASTER_API_KEY=YOUR_ACTUAL_TICKETMASTER_KEY
S3_BUCKET_NAME=YOUR_ACTUAL_BUCKET_NAME
AWS_REGION=us-east-1
FETCH_INTERVAL=1800
EOF

cat > /etc/systemd/system/unievent.service <<'SVCEOF'
[Unit]
Description=UniEvent Flask Application
After=network.target
[Service]
Type=simple
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
```

**Replace these 3 things in the script above before pasting:**
- `YOUR_GITHUB_USERNAME` → your actual GitHub username
- `YOUR_ACTUAL_TICKETMASTER_KEY` → the key from Step 0.2
- `YOUR_ACTUAL_BUCKET_NAME` → the bucket name from Step 2.8

5. Click **Launch instance**

### Step 2.10 — Launch EC2 Instance #2

Repeat Step 2.9 exactly, with these differences:
- **Name:** `UniEvent-App-2`
- **Subnet:** `UniEvent-Private-2` (different AZ for fault tolerance)
- **User data:** Same script (paste the same thing with the same keys)

**📸 SCREENSHOT: Both EC2 instances showing "Running" state**

### Step 2.11 — Create Target Group

1. **EC2** → Left sidebar: **Target Groups** → **Create target group**
2. Settings:
   - **Target type:** Instances
   - **Name:** `UniEvent-TG`
   - **Protocol:** HTTP, **Port:** `5000`
   - **VPC:** `UniEvent-VPC`
   - **Health check path:** `/health`
3. Click **Next**
4. Select **both** EC2 instances (`UniEvent-App-1` and `UniEvent-App-2`)
5. Click **Include as pending below**
6. Click **Create target group**

### Step 2.12 — Create the Application Load Balancer

⚠️ **ALB COSTS ~$0.60/day. Delete it immediately after screenshots.**

1. **EC2** → Left sidebar: **Load Balancers** → **Create load balancer**
2. Choose **Application Load Balancer** → **Create**
3. Settings:
   - **Name:** `UniEvent-ALB`
   - **Scheme:** Internet-facing
   - **IP address type:** IPv4
4. **Network mapping:**
   - **VPC:** `UniEvent-VPC`
   - **Mappings:** Check BOTH availability zones
     - us-east-1a → `UniEvent-Public-1`
     - us-east-1b → `UniEvent-Public-2`
5. **Security group:** Remove the default, add `UniEvent-ALB-SG`
6. **Listeners:**
   - Protocol: HTTP, Port: 80
   - Default action: Forward to → `UniEvent-TG`
7. Click **Create load balancer**

Wait 2-3 minutes for the ALB to become **Active**.

**📸 SCREENSHOT: ALB showing "Active" state**

### Step 2.13 — Get Your Website URL

1. Go to **Load Balancers** → Click `UniEvent-ALB`
2. Copy the **DNS name** (looks like: `UniEvent-ALB-1234567890.us-east-1.elb.amazonaws.com`)
3. Open in your browser: `http://` followed by that DNS name

**Wait 3-5 minutes** after launching the EC2 instances for the app to boot and pass health checks.

**📸 SCREENSHOT: UniEvent homepage loaded in browser**
**📸 SCREENSHOT: /health endpoint returning JSON**

### Step 2.14 — Verify Target Health

1. Go to **EC2** → **Target Groups** → `UniEvent-TG`
2. Click the **Targets** tab
3. Both instances should show **"healthy"**

If they show "unhealthy" or "initial", wait another 2-3 minutes. If still unhealthy after 5 minutes, the User Data script may have failed — see Troubleshooting section below.

**📸 SCREENSHOT: Target Group showing both targets as "healthy"**

### Step 2.15 — Test Fault Tolerance

This is the most important test for the assignment:

1. Go to **EC2** → **Instances** → Select `UniEvent-App-1`
2. Click **Instance state** → **Stop instance** → **Stop**
3. **Wait 90 seconds** (the ALB needs time to detect the failure)
4. **Refresh your website** — it should STILL WORK (served by App-2)
5. Go to **Target Groups** → `UniEvent-TG` → **Targets** tab
   - App-1 should show **"unhealthy"** or **"draining"**
   - App-2 should show **"healthy"**

**📸 SCREENSHOT: Website still working with one instance stopped**
**📸 SCREENSHOT: Target Group showing one healthy, one unhealthy**

6. Go back to **Instances** → Select `UniEvent-App-1` → **Instance state** → **Start instance**
7. Wait 2-3 minutes → Check Target Group again — both should be **"healthy"**

### Step 2.16 — Test Upload

1. Go to `http://<ALB-DNS>/upload`
2. Drag and drop any image
3. Click **Upload to S3**
4. You should see the S3 URL of the uploaded image

**📸 SCREENSHOT: Successful upload with S3 URL displayed**

Verify in S3:
1. Go to **S3** → Your bucket → `event-posters/` folder
2. Your uploaded image should be there

**📸 SCREENSHOT: S3 bucket showing the uploaded file**

---

## PHASE 3: CLEAN UP — DO THIS IMMEDIATELY

⚠️ **If you skip this, you WILL be charged. Do this right after taking all screenshots.**

Delete resources in this exact order (dependencies matter):

### Step 3.1 — Delete the Load Balancer

1. **EC2** → **Load Balancers** → Select `UniEvent-ALB`
2. **Actions** → **Delete load balancer**
3. Type `confirm` → **Delete**

### Step 3.2 — Delete the Target Group

1. **EC2** → **Target Groups** → Select `UniEvent-TG`
2. **Actions** → **Delete** → **Yes, delete**

### Step 3.3 — Terminate EC2 Instances

1. **EC2** → **Instances** → Select ALL UniEvent instances
2. **Instance state** → **Terminate instance** → **Terminate**
3. Wait for status to show **"Terminated"**

### Step 3.4 — Delete NAT Gateway (THIS IS THE EXPENSIVE ONE)

1. **VPC** → **NAT Gateways** → Select `UniEvent-NAT`
2. **Actions** → **Delete NAT gateway**
3. Type `delete` → **Delete**
4. Wait 1-2 minutes until it disappears

### Step 3.5 — Release Elastic IP

1. **VPC** → **Elastic IP addresses**
2. Select the IP that was used by the NAT Gateway (it will show "Not associated")
3. **Actions** → **Release Elastic IP addresses** → **Release**

### Step 3.6 — Delete S3 Bucket

1. **S3** → Select your bucket
2. Click **Empty** → type `permanently delete` → **Empty**
3. Go back → Select the bucket → **Delete** → type the bucket name → **Delete**

### Step 3.7 — Delete Security Groups

1. **VPC** → **Security Groups**
2. Delete `UniEvent-EC2-SG` first (it references ALB SG)
3. Then delete `UniEvent-ALB-SG`
4. (You cannot delete the "default" security group — that is normal)

### Step 3.8 — Delete Subnets

1. **VPC** → **Subnets**
2. Select all 4 UniEvent subnets → **Actions** → **Delete subnet** → **Delete**

### Step 3.9 — Delete Route Tables

1. **VPC** → **Route Tables**
2. Delete `UniEvent-Public-RT` and `UniEvent-Private-RT`
3. (Do NOT delete the "Main" route table — it gets deleted with the VPC)

### Step 3.10 — Detach and Delete Internet Gateway

1. **VPC** → **Internet Gateways** → Select `UniEvent-IGW`
2. **Actions** → **Detach from VPC** → **Detach**
3. **Actions** → **Delete internet gateway** → Type `delete` → **Delete**

### Step 3.11 — Delete VPC

1. **VPC** → **Your VPCs** → Select `UniEvent-VPC`
2. **Actions** → **Delete VPC** → Type `delete` → **Delete**

### Step 3.12 — Delete IAM Role

1. **IAM** → **Roles** → Search for `UniEvent-EC2-Role`
2. Click on it → **Delete** → Type the role name → **Delete**

### Step 3.13 — Verify Everything is Gone

Go to each service and confirm no UniEvent resources remain:
- EC2 Instances: all terminated
- Load Balancers: empty
- Target Groups: empty
- S3: bucket deleted
- VPC: UniEvent-VPC gone
- NAT Gateways: none
- Elastic IPs: none
- IAM Roles: UniEvent-EC2-Role gone

**OR** run the cleanup script instead of doing this manually:
```bash
bash scripts/cleanup.sh
```

---

## PHASE 4: Alternative — CLI Script Deployment (Linux/Mac Only)

⚠️ **This method requires bash (Linux/Mac). If you are on Windows, skip to Phase 5 (CloudFormation) or use Phase 2 (Manual Console).**

If you have WSL (Windows Subsystem for Linux) installed, you can run bash scripts through it:
```powershell
wsl bash scripts/deploy-aws-cli.sh
```

Otherwise, this phase is not for you. Use Phase 2 or Phase 5 instead.

### Step 4.1 — Edit the Script

Open `scripts/deploy-aws-cli.sh` and edit ONLY these 4 lines at the top:

```bash
REGION="us-east-1"
KEY_PAIR="unievent-key"
TICKETMASTER_KEY="your-actual-ticketmaster-api-key"
GITHUB_REPO="https://github.com/YOUR_USERNAME/Assignment1_AWS_CE.git"
```

### Step 4.2 — Run It

```bash
bash scripts/deploy-aws-cli.sh
```

It will print progress for each step and give you the ALB URL at the end. Takes about 5 minutes (NAT Gateway creation is the slowest part).

### Step 4.3 — Clean Up

```bash
bash scripts/cleanup.sh
```

---

## PHASE 5: Alternative — CloudFormation (Works on Windows)

This method works on Windows because it uses the AWS CLI which you installed in Step 0.3.

### Step 5.1 — Replace GitHub Username

Open `infrastructure\cloudformation.yaml` in Notepad or VS Code. Press Ctrl+H (Find and Replace):
- Find: `<YOUR_GITHUB_USERNAME>`
- Replace: your actual GitHub username
- Click "Replace All" (it appears twice)

Save the file.

### Step 5.2 — Deploy

Open PowerShell and run (all one command — copy the entire block):
```powershell
aws cloudformation create-stack `
  --stack-name UniEvent `
  --template-body file://infrastructure/cloudformation.yaml `
  --parameters `
    ParameterKey=TicketmasterApiKey,ParameterValue=YOUR_TICKETMASTER_KEY `
    ParameterKey=KeyPairName,ParameterValue=unievent-key `
  --capabilities CAPABILITY_NAMED_IAM `
  --region us-east-1
```

Replace `YOUR_TICKETMASTER_KEY` with your actual key.

**Note:** In PowerShell, line continuation uses backtick `` ` `` not backslash `\`.

### Step 5.3 — Wait and Get URL

```powershell
# Check status (wait until it says CREATE_COMPLETE — takes 5-10 minutes)
aws cloudformation describe-stacks --stack-name UniEvent `
  --query "Stacks[0].StackStatus" --output text

# Get the website URL
aws cloudformation describe-stacks --stack-name UniEvent `
  --query "Stacks[0].Outputs[?OutputKey=='ALBEndpoint'].OutputValue" --output text
```

### Step 5.4 — Clean Up (Deletes EVERYTHING in one command)

```powershell
# First get the bucket name
$BUCKET = aws cloudformation describe-stacks --stack-name UniEvent `
  --query "Stacks[0].Outputs[?OutputKey=='S3BucketName'].OutputValue" --output text

# Empty the S3 bucket (CloudFormation cannot delete non-empty buckets)
aws s3 rm "s3://$BUCKET" --recursive

# Delete the entire stack
aws cloudformation delete-stack --stack-name UniEvent

# Verify it is deleting
aws cloudformation describe-stacks --stack-name UniEvent `
  --query "Stacks[0].StackStatus" --output text
```

---

## Troubleshooting

### "unhealthy" targets in the Target Group

The EC2 instances need 3-5 minutes to boot, clone the repo, install packages, and start the app. If still unhealthy after 5 minutes:

1. The User Data script may have failed. Check by connecting via Session Manager:
   - Go to **EC2** → Select the instance → **Connect** → **Session Manager** → **Connect**
   - This opens a terminal in your browser (no SSH needed, no key pair needed)
   - Run: `sudo cat /var/log/cloud-init-output.log | tail -50`
   - Look for errors (usually a typo in the GitHub URL or API key)

2. Check if the app is running (in the Session Manager terminal):
   ```bash
   sudo systemctl status unievent
   curl http://localhost:5000/health
   ```

3. If the clone failed (wrong GitHub username), run in Session Manager:
   ```bash
   sudo rm -rf /opt/unievent
   sudo git clone https://github.com/CORRECT_USERNAME/Assignment1_AWS_CE.git /opt/unievent
   cd /opt/unievent/app
   sudo pip3 install -r requirements.txt
   sudo systemctl restart unievent
   ```

**Note:** The commands above run ON the EC2 instance (which is Linux), not on your Windows PC. You type them into the Session Manager browser terminal.

### Cannot connect to the website at all

1. Check ALB is in **Active** state (not Provisioning)
2. Check you are using `http://` not `https://` (we did not set up SSL)
3. Check the ALB security group allows port 80 from 0.0.0.0/0
4. Check the ALB listener is forwarding to the correct target group
5. Wait at least 5 minutes after launching — instances need time to boot

### S3 upload fails

1. Check the IAM role is attached to the EC2 instances (Step 2.9, Advanced details)
2. Check the bucket name in your User Data script matches the actual S3 bucket name exactly
3. Check the bucket policy allows public read on the correct prefixes

### Events page shows "No Events Available"

1. The Ticketmaster API key may be wrong — check for typos in the User Data script
2. The app may still be doing its first fetch — wait 30 seconds and refresh
3. Click the **Refresh** button on the page to trigger a manual fetch

---

## Which Deployment Method Should You Use?

| Method | Time | Works on Windows? | Screenshots | Best For |
|--------|------|-------------------|-------------|---------|
| **Manual Console** (Phase 2) | 30-45 min | **Yes** | Easy — you are already in the console | **The assignment submission** |
| **CLI Script** (Phase 4) | 5 min | **No** — needs bash/Linux/WSL | Harder | Linux/Mac users only |
| **CloudFormation** (Phase 5) | 5 min | **Yes** — needs AWS CLI installed | Harder | Quick deploy + easy cleanup |

**Recommendation for you (Windows user):** Do the **Manual Console** method (Phase 2) for your assignment. It works entirely in your web browser, gives you the best screenshots, and matches what your professor expects. If you want a quick test first, use **CloudFormation** (Phase 5) since it works in PowerShell.
