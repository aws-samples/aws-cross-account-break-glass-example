#!/bin/bash

# Break Glass User Multi-Region Deployment Script
# Deploys monitoring to ALL AWS regions for comprehensive security coverage

set -e

# All AWS regions where ConsoleLogin events can occur
ALL_REGIONS=(
    "us-east-1" "us-east-2" "us-west-1" "us-west-2"
    "eu-north-1" "eu-central-1" "eu-west-1" "eu-west-2" "eu-west-3" "eu-south-1" "eu-south-2" "eu-central-2"
    "ap-southeast-2" "ap-southeast-1" "ap-northeast-1" "ap-northeast-2" "ap-northeast-3" 
    "ap-south-1" "ap-south-2" "ap-southeast-3" "ap-southeast-4" "ap-southeast-5" "ap-southeast-7" 
    "ap-east-1" "ap-east-2"
    "ca-central-1" "ca-west-1"
    "sa-east-1"
    "af-south-1"
    "me-south-1" "me-central-1"
    "il-central-1"
    "mx-central-1"
)



# Get account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

echo "🔐 Break Glass User Multi-Region Security Deployment"
echo "================================================="
echo ""

# Prompt for email address
while [ -z "$EMAIL_ADDRESS" ]; do
    read -p "📧 Enter email address for security notifications: " EMAIL_ADDRESS
    if [ -z "$EMAIL_ADDRESS" ]; then
        echo "❌ Email address is required"
    fi
done

# Prompt for primary region with default
echo ""
echo "🏠 Primary region (where SNS topic will be created)"
read -p "Enter primary region [Default region is us-east-1]: " PRIMARY_REGION
PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}

# Confirmation prompt
echo ""
echo "📋 Deployment Summary:"
echo "   📧 Email: $EMAIL_ADDRESS"
echo "   🏠 Primary region: $PRIMARY_REGION"
echo "   🔢 Account ID: $ACCOUNT_ID"
echo "   📍 Total regions: ${#ALL_REGIONS[@]}"
echo ""
read -p "🚀 Deploy to ALL regions? (y/N): " CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "❌ Deployment cancelled"
    exit 0
fi

echo "🚀 Deploying Break Glass monitoring to ALL AWS regions"

# Initialize terraform
echo ""
echo "🔧 Initializing Terraform..."
terraform init

echo "✅ Validating Terraform configuration..."
terraform validate

# Progress bar function
progress_bar() {
    local pid=$1
    local width=20
    local i=0
    local yellow='\033[33m'
    local green='\033[32m'
    local reset='\033[0m'
    while kill -0 $pid 2>/dev/null; do
        printf "\r${yellow}["
        for ((j=0; j<width; j++)); do
            if [ $j -lt $((i % width)) ]; then
                printf "="
            else
                printf " "
            fi
        done
        printf "] Working...${reset}"
        ((i++))
        sleep 0.5
    done
    printf "\r${green}[$(printf '=%.0s' $(seq 1 $width))] ✅ Complete${reset}\n"
}

# Deploy primary region first
echo ""
echo "🏠 Deploying PRIMARY region: $PRIMARY_REGION"
terraform workspace select $PRIMARY_REGION 2>/dev/null || terraform workspace new $PRIMARY_REGION
(
    AWS_DEFAULT_REGION=$PRIMARY_REGION terraform apply -auto-approve \
        -var="emailAddress=$EMAIL_ADDRESS" 2>&1 | grep -E "(Plan:|Apply complete!|Error:|Warning:|⚠️|❌)"
) &
progress_bar $!
wait

# Deploy all secondary regions
for region in "${ALL_REGIONS[@]}"; do
    if [ "$region" != "$PRIMARY_REGION" ]; then
        echo ""
        echo "🌍 Deploying region: $region"
        
        # Check if region is enabled/accessible
        if aws ec2 describe-regions --region-names "$region" --region "$region" >/dev/null 2>&1; then
            terraform workspace select $region 2>/dev/null || terraform workspace new $region
            (
                AWS_DEFAULT_REGION=$region terraform apply -auto-approve \
                    -var="emailAddress=$EMAIL_ADDRESS" \
                    -var="primary_region=$PRIMARY_REGION" \
                    -var="primary_account_id=$ACCOUNT_ID" 2>&1 | grep -E "(Plan:|Apply complete!|Error:|Warning:|⚠️|❌)"
            ) &
            progress_bar $!
            wait || {
                echo "⚠️  Failed to deploy to $region (region may not be enabled)"
            }
        else
            echo "⚠️  Skipping $region (region not enabled in account)"
        fi
    fi
done

echo ""
echo "✅ Break Glass monitoring deployment complete!"
echo "📧 Check your email to confirm SNS subscription"
echo "🔍 Monitoring active in all accessible AWS regions"