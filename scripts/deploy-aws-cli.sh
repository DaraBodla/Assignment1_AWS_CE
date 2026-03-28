#!/bin/bash
# ===========================================================================
# UniEvent — AWS CLI Deployment Script
# Deploys the full infrastructure using AWS CLI commands.
# Run each section step by step, or execute the whole script.
#
# Prerequisites:
#   - AWS CLI v2 configured (aws configure)
#   - A Key Pair created in the target region
#   - A Ticketmaster API Key
# ===========================================================================
set -euo pipefail

# ── Configuration (EDIT THESE) ─────────────────────────────────────────
REGION="us-east-1"
KEY_PAIR="your-keypair-name"
TICKETMASTER_KEY="your-ticketmaster-api-key"
GITHUB_REPO="https://github.com/YOUR_USERNAME/Assignment1_AWS_CE.git"
INSTANCE_TYPE="t2.micro"
# -----------------------------------------------------------------------

echo "╔══════════════════════════════════════════════╗"
echo "║   UniEvent — AWS Infrastructure Deployment   ║"
echo "╚══════════════════════════════════════════════╝"

# ── 1. VPC ─────────────────────────────────────────────────────────────
echo "→ [1/10] Creating VPC…"
VPC_ID=$(aws ec2 create-vpc \
    --cidr-block 10.0.0.0/16 \
    --tag-specifications 'ResourceType=vpc,Tags=[{Key=Name,Value=UniEvent-VPC}]' \
    --region "$REGION" \
    --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id "$VPC_ID" --enable-dns-hostnames --region "$REGION"
echo "  VPC: $VPC_ID"

# ── 2. Internet Gateway ───────────────────────────────────────────────
echo "→ [2/10] Creating Internet Gateway…"
IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications 'ResourceType=internet-gateway,Tags=[{Key=Name,Value=UniEvent-IGW}]' \
    --region "$REGION" \
    --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id "$VPC_ID" --internet-gateway-id "$IGW_ID" --region "$REGION"
echo "  IGW: $IGW_ID"

# ── 3. Subnets ────────────────────────────────────────────────────────
echo "→ [3/10] Creating Subnets…"
AZ1="${REGION}a"
AZ2="${REGION}b"

PUB1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.1.0/24 --availability-zone "$AZ1" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=UniEvent-Public-1}]' \
    --region "$REGION" --query 'Subnet.SubnetId' --output text)
PUB2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.2.0/24 --availability-zone "$AZ2" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=UniEvent-Public-2}]' \
    --region "$REGION" --query 'Subnet.SubnetId' --output text)
PRIV1=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.10.0/24 --availability-zone "$AZ1" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=UniEvent-Private-1}]' \
    --region "$REGION" --query 'Subnet.SubnetId' --output text)
PRIV2=$(aws ec2 create-subnet --vpc-id "$VPC_ID" --cidr-block 10.0.20.0/24 --availability-zone "$AZ2" \
    --tag-specifications 'ResourceType=subnet,Tags=[{Key=Name,Value=UniEvent-Private-2}]' \
    --region "$REGION" --query 'Subnet.SubnetId' --output text)

# Enable auto-assign public IP on public subnets
aws ec2 modify-subnet-attribute --subnet-id "$PUB1" --map-public-ip-on-launch --region "$REGION"
aws ec2 modify-subnet-attribute --subnet-id "$PUB2" --map-public-ip-on-launch --region "$REGION"
echo "  Public:  $PUB1, $PUB2"
echo "  Private: $PRIV1, $PRIV2"

# ── 4. Route Tables ───────────────────────────────────────────────────
echo "→ [4/10] Configuring Route Tables…"
# Public route table
PUB_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=UniEvent-Public-RT}]' \
    --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PUB_RT" --destination-cidr-block 0.0.0.0/0 --gateway-id "$IGW_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUB_RT" --subnet-id "$PUB1" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PUB_RT" --subnet-id "$PUB2" --region "$REGION" > /dev/null

# NAT Gateway
echo "→ [5/10] Creating NAT Gateway (takes ~2 min)…"
EIP_ALLOC=$(aws ec2 allocate-address --domain vpc --region "$REGION" --query 'AllocationId' --output text)
NAT_ID=$(aws ec2 create-nat-gateway --subnet-id "$PUB1" --allocation-id "$EIP_ALLOC" \
    --tag-specifications 'ResourceType=natgateway,Tags=[{Key=Name,Value=UniEvent-NAT}]' \
    --region "$REGION" --query 'NatGateway.NatGatewayId' --output text)
echo "  Waiting for NAT Gateway to become available…"
aws ec2 wait nat-gateway-available --nat-gateway-ids "$NAT_ID" --region "$REGION"
echo "  NAT: $NAT_ID"

# Private route table
PRIV_RT=$(aws ec2 create-route-table --vpc-id "$VPC_ID" \
    --tag-specifications 'ResourceType=route-table,Tags=[{Key=Name,Value=UniEvent-Private-RT}]' \
    --region "$REGION" --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id "$PRIV_RT" --destination-cidr-block 0.0.0.0/0 --nat-gateway-id "$NAT_ID" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRIV_RT" --subnet-id "$PRIV1" --region "$REGION" > /dev/null
aws ec2 associate-route-table --route-table-id "$PRIV_RT" --subnet-id "$PRIV2" --region "$REGION" > /dev/null

# ── 5. Security Groups ────────────────────────────────────────────────
echo "→ [6/10] Creating Security Groups…"
ALB_SG=$(aws ec2 create-security-group --group-name UniEvent-ALB-SG \
    --description "Allow HTTP to ALB" --vpc-id "$VPC_ID" \
    --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 80 --cidr 0.0.0.0/0 --region "$REGION" > /dev/null
aws ec2 authorize-security-group-ingress --group-id "$ALB_SG" --protocol tcp --port 443 --cidr 0.0.0.0/0 --region "$REGION" > /dev/null

EC2_SG=$(aws ec2 create-security-group --group-name UniEvent-EC2-SG \
    --description "Allow from ALB only" --vpc-id "$VPC_ID" \
    --region "$REGION" --query 'GroupId' --output text)
aws ec2 authorize-security-group-ingress --group-id "$EC2_SG" --protocol tcp --port 5000 --source-group "$ALB_SG" --region "$REGION" > /dev/null
echo "  ALB SG: $ALB_SG"
echo "  EC2 SG: $EC2_SG"

# ── 6. IAM Role ───────────────────────────────────────────────────────
echo "→ [7/10] Creating IAM Role…"
cat > /tmp/trust-policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {"Service": "ec2.amazonaws.com"},
    "Action": "sts:AssumeRole"
  }]
}
EOF

aws iam create-role --role-name UniEvent-EC2-Role \
    --assume-role-policy-document file:///tmp/trust-policy.json > /dev/null 2>&1 || true

aws iam attach-role-policy --role-name UniEvent-EC2-Role \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true

aws iam create-instance-profile --instance-profile-name UniEvent-EC2-Profile 2>/dev/null || true
aws iam add-role-to-instance-profile --instance-profile-name UniEvent-EC2-Profile \
    --role-name UniEvent-EC2-Role 2>/dev/null || true
echo "  IAM Role: UniEvent-EC2-Role"

# ── 7. S3 Bucket ──────────────────────────────────────────────────────
echo "→ [8/10] Creating S3 Bucket…"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="unievent-media-${ACCOUNT_ID}"
aws s3 mb "s3://$BUCKET" --region "$REGION" 2>/dev/null || echo "  Bucket may already exist"

# Add S3 policy to IAM role
cat > /tmp/s3-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject","s3:GetObject","s3:ListBucket","s3:DeleteObject"],
    "Resource": ["arn:aws:s3:::$BUCKET","arn:aws:s3:::$BUCKET/*"]
  }]
}
EOF
aws iam put-role-policy --role-name UniEvent-EC2-Role \
    --policy-name UniEvent-S3-Access \
    --policy-document file:///tmp/s3-policy.json
echo "  Bucket: $BUCKET"

# ── 8. EC2 Instances ──────────────────────────────────────────────────
echo "→ [9/10] Launching EC2 Instances…"
AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
    --region "$REGION" --query 'Parameters[0].Value' --output text)

USER_DATA=$(cat <<UDEOF
#!/bin/bash
set -euo pipefail
yum update -y
yum install -y python3 python3-pip git
git clone $GITHUB_REPO /opt/unievent
cd /opt/unievent/app
pip3 install -r requirements.txt
cat > /opt/unievent/.env <<EOF
FLASK_SECRET_KEY=prod-secret-$(openssl rand -hex 16)
TICKETMASTER_API_KEY=$TICKETMASTER_KEY
S3_BUCKET_NAME=$BUCKET
AWS_REGION=$REGION
FETCH_INTERVAL=1800
EOF
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
UDEOF
)

# Wait for instance profile to propagate
sleep 10

EC2_1=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_PAIR" --subnet-id "$PRIV1" \
    --security-group-ids "$EC2_SG" \
    --iam-instance-profile Name=UniEvent-EC2-Profile \
    --user-data "$USER_DATA" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=UniEvent-App-1}]' \
    --region "$REGION" --query 'Instances[0].InstanceId' --output text)

EC2_2=$(aws ec2 run-instances \
    --image-id "$AMI_ID" --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_PAIR" --subnet-id "$PRIV2" \
    --security-group-ids "$EC2_SG" \
    --iam-instance-profile Name=UniEvent-EC2-Profile \
    --user-data "$USER_DATA" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=UniEvent-App-2}]' \
    --region "$REGION" --query 'Instances[0].InstanceId' --output text)
echo "  EC2 #1: $EC2_1"
echo "  EC2 #2: $EC2_2"

# ── 9. Application Load Balancer ──────────────────────────────────────
echo "→ [10/10] Creating ALB & Target Group…"
TG_ARN=$(aws elbv2 create-target-group \
    --name UniEvent-TG --protocol HTTP --port 5000 \
    --vpc-id "$VPC_ID" --target-type instance \
    --health-check-path /health \
    --health-check-interval-seconds 30 \
    --healthy-threshold-count 2 \
    --unhealthy-threshold-count 3 \
    --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 register-targets --target-group-arn "$TG_ARN" \
    --targets "Id=$EC2_1,Port=5000" "Id=$EC2_2,Port=5000" --region "$REGION"

ALB_ARN=$(aws elbv2 create-load-balancer \
    --name UniEvent-ALB --scheme internet-facing --type application \
    --subnets "$PUB1" "$PUB2" --security-groups "$ALB_SG" \
    --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text)

aws elbv2 create-listener --load-balancer-arn "$ALB_ARN" \
    --protocol HTTP --port 80 \
    --default-actions "Type=forward,TargetGroupArn=$TG_ARN" \
    --region "$REGION" > /dev/null

ALB_DNS=$(aws elbv2 describe-load-balancers --load-balancer-arns "$ALB_ARN" \
    --region "$REGION" --query 'LoadBalancers[0].DNSName' --output text)

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║          ✓ DEPLOYMENT COMPLETE!              ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "  ALB URL:  http://$ALB_DNS"
echo "  Health:   http://$ALB_DNS/health"
echo "  API:      http://$ALB_DNS/api/events"
echo ""
echo "  VPC:      $VPC_ID"
echo "  EC2 #1:   $EC2_1 (AZ: $AZ1)"
echo "  EC2 #2:   $EC2_2 (AZ: $AZ2)"
echo "  S3:       $BUCKET"
echo ""
echo "  ⏳ Wait 3-5 minutes for instances to boot and"
echo "     pass ALB health checks before testing."
echo ""
