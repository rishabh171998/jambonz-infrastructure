#!/bin/bash
# Script to set up DNS records for Jambonz ALB

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <alb-dns-name> [hosted-zone-id]"
  echo ""
  echo "Example:"
  echo "  $0 jambonz-alb-123456789.ap-south-1.elb.amazonaws.com Z1234567890ABC"
  echo ""
  echo "If hosted-zone-id is not provided, will try to find it automatically"
  exit 1
fi

ALB_DNS_NAME="$1"
HOSTED_ZONE_ID="${2:-}"

# Get ALB zone ID (standard for all ALBs in ap-south-1)
ALB_ZONE_ID="Z3VO1THU9YC4UR"  # ap-south-1 ALB zone ID

echo "=========================================="
echo "Setting up DNS Records for Jambonz"
echo "=========================================="
echo ""
echo "ALB DNS Name: $ALB_DNS_NAME"
echo "ALB Zone ID: $ALB_ZONE_ID"
echo ""

# Find hosted zone ID if not provided
if [ -z "$HOSTED_ZONE_ID" ]; then
  echo "Finding hosted zone for graine.ai..."
  HOSTED_ZONE_ID=$(aws route53 list-hosted-zones \
    --query "HostedZones[?Name=='graine.ai.'].Id" \
    --output text | cut -d'/' -f3 2>/dev/null || echo "")
  
  if [ -z "$HOSTED_ZONE_ID" ]; then
    echo "❌ Could not find hosted zone for graine.ai"
    echo "   Please provide hosted zone ID manually"
    exit 1
  fi
fi

echo "Hosted Zone ID: $HOSTED_ZONE_ID"
echo ""

# Create DNS records
echo "Creating DNS records..."

# telephony.graine.ai
echo "1. Creating A record for telephony.graine.ai..."
aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"telephony.graine.ai\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE_ID\",
          \"DNSName\": \"$ALB_DNS_NAME\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }" > /dev/null

if [ $? -eq 0 ]; then
  echo "✅ telephony.graine.ai → $ALB_DNS_NAME"
else
  echo "❌ Failed to create DNS record"
  exit 1
fi

# sipwebapp.graine.ai
echo ""
echo "2. Creating A record for sipwebapp.graine.ai..."
aws route53 change-resource-record-sets \
  --hosted-zone-id "$HOSTED_ZONE_ID" \
  --change-batch "{
    \"Changes\": [{
      \"Action\": \"UPSERT\",
      \"ResourceRecordSet\": {
        \"Name\": \"sipwebapp.graine.ai\",
        \"Type\": \"A\",
        \"AliasTarget\": {
          \"HostedZoneId\": \"$ALB_ZONE_ID\",
          \"DNSName\": \"$ALB_DNS_NAME\",
          \"EvaluateTargetHealth\": true
        }
      }
    }]
  }" > /dev/null

if [ $? -eq 0 ]; then
  echo "✅ sipwebapp.graine.ai → $ALB_DNS_NAME"
else
  echo "❌ Failed to create DNS record"
  exit 1
fi

# sip.graine.ai (for SIP/RTP - direct EC2, not ALB)
echo ""
echo "3. Note: sip.graine.ai should point to EC2 instance IP (not ALB)"
echo "   SIP/RTP traffic goes directly to EC2, not through ALB"
echo ""

echo "=========================================="
echo "✅ DNS Records Created"
echo "=========================================="
echo ""
echo "Domains:"
echo "  - telephony.graine.ai → API Server (HTTPS on port 443)"
echo "  - sipwebapp.graine.ai → Webapp (HTTPS on port 8443)"
echo "  - sip.graine.ai → EC2 Instance (SIP/RTP, direct access)"
echo ""
echo "Wait a few minutes for DNS propagation, then test:"
echo "  curl https://telephony.graine.ai/api/v1/Accounts -H \"Authorization: Bearer YOUR_TOKEN\""
echo "  open https://sipwebapp.graine.ai"
echo ""

