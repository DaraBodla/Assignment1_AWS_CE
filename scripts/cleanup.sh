#!/bin/bash
# ===========================================================================
# UniEvent — Cleanup Script
# Tears down all AWS resources to avoid ongoing charges.
# ===========================================================================
set -euo pipefail

REGION="us-east-1"

echo "╔══════════════════════════════════════════════╗"
echo "║   UniEvent — Resource Cleanup                ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "⚠  This will DELETE all UniEvent AWS resources."
read -p "   Are you sure? [y/N] " -n 1 -r
echo
[[ ! $REPLY =~ ^[Yy]$ ]] && exit 0

echo "→ Deleting ALB & Target Group…"
ALB_ARN=$(aws elbv2 describe-load-balancers --names UniEvent-ALB --region "$REGION" --query 'LoadBalancers[0].LoadBalancerArn' --output text 2>/dev/null || echo "")
if [ -n "$ALB_ARN" ] && [ "$ALB_ARN" != "None" ]; then
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn "$ALB_ARN" --region "$REGION" --query 'Listeners[].ListenerArn' --output text 2>/dev/null || echo "")
    for l in $LISTENERS; do aws elbv2 delete-listener --listener-arn "$l" --region "$REGION" 2>/dev/null || true; done
    aws elbv2 delete-load-balancer --load-balancer-arn "$ALB_ARN" --region "$REGION" 2>/dev/null || true
fi
TG_ARN=$(aws elbv2 describe-target-groups --names UniEvent-TG --region "$REGION" --query 'TargetGroups[0].TargetGroupArn' --output text 2>/dev/null || echo "")
if [ -n "$TG_ARN" ] && [ "$TG_ARN" != "None" ]; then
    aws elbv2 delete-target-group --target-group-arn "$TG_ARN" --region "$REGION" 2>/dev/null || true
fi

echo "→ Terminating EC2 instances…"
INSTANCES=$(aws ec2 describe-instances --filters "Name=tag:Name,Values=UniEvent-*" "Name=instance-state-name,Values=running,stopped" \
    --region "$REGION" --query 'Reservations[].Instances[].InstanceId' --output text 2>/dev/null || echo "")
if [ -n "$INSTANCES" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCES --region "$REGION" > /dev/null
    echo "  Waiting for termination…"
    aws ec2 wait instance-terminated --instance-ids $INSTANCES --region "$REGION" 2>/dev/null || true
fi

echo "→ Deleting S3 bucket…"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="unievent-media-${ACCOUNT_ID}"
aws s3 rb "s3://$BUCKET" --force 2>/dev/null || true

echo "→ Deleting NAT Gateway…"
NAT_IDS=$(aws ec2 describe-nat-gateways --filter "Name=tag:Name,Values=UniEvent-NAT" \
    --region "$REGION" --query 'NatGateways[?State!=`deleted`].NatGatewayId' --output text 2>/dev/null || echo "")
for n in $NAT_IDS; do
    aws ec2 delete-nat-gateway --nat-gateway-id "$n" --region "$REGION" > /dev/null
done
[ -n "$NAT_IDS" ] && echo "  Waiting for NAT deletion…" && sleep 60

echo "→ Releasing Elastic IPs…"
EIPS=$(aws ec2 describe-addresses --region "$REGION" --query 'Addresses[?AssociationId==null].AllocationId' --output text 2>/dev/null || echo "")
for e in $EIPS; do aws ec2 release-address --allocation-id "$e" --region "$REGION" 2>/dev/null || true; done

echo "→ Deleting Security Groups…"
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=UniEvent-VPC" \
    --region "$REGION" --query 'Vpcs[0].VpcId' --output text 2>/dev/null || echo "")
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    SGS=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" \
        --region "$REGION" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    for sg in $SGS; do aws ec2 delete-security-group --group-id "$sg" --region "$REGION" 2>/dev/null || true; done
fi

echo "→ Deleting Subnets & Route Tables…"
if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    SUBNETS=$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" \
        --region "$REGION" --query 'Subnets[].SubnetId' --output text 2>/dev/null || echo "")
    for s in $SUBNETS; do aws ec2 delete-subnet --subnet-id "$s" --region "$REGION" 2>/dev/null || true; done

    RTS=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" \
        --region "$REGION" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
    for rt in $RTS; do
        ASSOCS=$(aws ec2 describe-route-tables --route-table-ids "$rt" --region "$REGION" \
            --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text 2>/dev/null || echo "")
        for a in $ASSOCS; do aws ec2 disassociate-route-table --association-id "$a" --region "$REGION" 2>/dev/null || true; done
        aws ec2 delete-route-table --route-table-id "$rt" --region "$REGION" 2>/dev/null || true
    done

    echo "→ Detaching & Deleting IGW…"
    IGWS=$(aws ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" \
        --region "$REGION" --query 'InternetGateways[].InternetGatewayId' --output text 2>/dev/null || echo "")
    for igw in $IGWS; do
        aws ec2 detach-internet-gateway --internet-gateway-id "$igw" --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
        aws ec2 delete-internet-gateway --internet-gateway-id "$igw" --region "$REGION" 2>/dev/null || true
    done

    echo "→ Deleting VPC…"
    aws ec2 delete-vpc --vpc-id "$VPC_ID" --region "$REGION" 2>/dev/null || true
fi

echo "→ Cleaning IAM resources…"
aws iam remove-role-from-instance-profile --instance-profile-name UniEvent-EC2-Profile --role-name UniEvent-EC2-Role 2>/dev/null || true
aws iam delete-instance-profile --instance-profile-name UniEvent-EC2-Profile 2>/dev/null || true
aws iam delete-role-policy --role-name UniEvent-EC2-Role --policy-name UniEvent-S3-Access 2>/dev/null || true
aws iam detach-role-policy --role-name UniEvent-EC2-Role --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore 2>/dev/null || true
aws iam delete-role --role-name UniEvent-EC2-Role 2>/dev/null || true

echo ""
echo "✓ All UniEvent resources have been deleted."
echo ""
