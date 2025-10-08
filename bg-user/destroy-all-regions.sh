#!/bin/bash

# Break Glass User Multi-Region Cleanup Script
# Removes monitoring from ALL AWS regions

set -e

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

# Get email for terraform variable (though not used in destroy)
while [ -z "$EMAIL_ADDRESS" ]; do
    read -p "📧 Enter email address used for security notifications when previously deploying: " EMAIL_ADDRESS
    if [ -z "$EMAIL_ADDRESS" ]; then
        echo "❌ Email address is required"
    fi
done

# Get primary region used during deployment
echo ""
echo "🏠 Primary region (where SNS topic was created during deployment)"
read -p "Enter primary region used during deployment [Default is us-east-1]: " PRIMARY_REGION
PRIMARY_REGION=${PRIMARY_REGION:-"us-east-1"}

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

echo ""
echo "🗑️  Destroying Break Glass monitoring in ALL regions"
echo "🏠 Primary region: $PRIMARY_REGION"

# Destroy secondary regions first
for region in "${ALL_REGIONS[@]}"; do
    if [ "$region" != "$PRIMARY_REGION" ]; then
        echo "🌍 Destroying region: $region"
        if terraform workspace list | grep -q "$region"; then
            terraform workspace select $region
            (
                AWS_DEFAULT_REGION=$region terraform destroy -auto-approve -var="emailAddress=$EMAIL_ADDRESS" 2>&1 | grep -E "(Plan:|Destroy complete!|Error:|Warning:|⚠️|❌)"
            ) &
            progress_bar $!
            wait || echo "⚠️  Failed to destroy $region"
            terraform workspace select default
            terraform workspace delete $region
        else
            echo "⚠️  Workspace $region not found, skipping"
        fi
    fi
done

# Destroy primary region last
echo "🏠 Destroying PRIMARY region: $PRIMARY_REGION"
if terraform workspace list | grep -q "$PRIMARY_REGION"; then
    terraform workspace select $PRIMARY_REGION
    (
        AWS_DEFAULT_REGION=$PRIMARY_REGION terraform destroy -auto-approve -var="emailAddress=$EMAIL_ADDRESS" 2>&1 | grep -E "(Plan:|Destroy complete!|Error:|Warning:|⚠️|❌)"
    ) &
    progress_bar $!
    wait
    terraform workspace select default
    terraform workspace delete $PRIMARY_REGION
else
    echo "⚠️  Primary region workspace not found"
fi

echo "✅ All Break Glass monitoring resources destroyed"