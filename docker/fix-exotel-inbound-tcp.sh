#!/bin/bash
# Fix Exotel inbound gateways to use TCP (not UDP) for signaling

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Fixing Exotel Inbound Gateways (TCP)"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "Found carrier SID: $CARRIER_SID"
echo ""

# According to Exotel docs:
# - Signaling: TCP port 5070 (not UDP 5060)
# - Media IPs: 182.76.143.61, 122.15.8.184, 14.194.10.247, 61.246.82.75
# - These media IPs are for RTP, not SIP signaling

echo "Current inbound gateways:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, inbound, outbound FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;" 2>/dev/null
echo ""

echo "⚠️  IMPORTANT: Exotel uses TCP port 5070 for SIP signaling (not UDP 5060)"
echo "   The IPs you have (182.76.143.61, etc.) are MEDIA IPs, not signaling IPs."
echo ""
echo "   For inbound SIP signaling, you need Exotel's signaling server IPs."
echo "   Contact Exotel support to get the actual IP addresses of:"
echo "   - pstn.in2.exotel.com (Mumbai DC)"
echo "   - pstn.in4.exotel.com (Mumbai Cloud)"
echo ""
echo "   OR: Since you're using FQDN for outbound, you can configure inbound"
echo "   to accept calls from any IP (less secure) or use the media IPs if"
echo "   Exotel uses the same IPs for signaling and media."
echo ""

read -p "Do you want to update inbound gateways to TCP port 5070? (y/n): " UPDATE_INBOUND

if [ "$UPDATE_INBOUND" != "y" ]; then
  echo "Skipping inbound gateway updates."
  exit 0
fi

# Update all inbound gateways to TCP port 5070
echo ""
echo "Updating inbound gateways to TCP port 5070..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET 
  port = 5070,
  protocol = 'tcp'
WHERE voip_carrier_sid = '$CARRIER_SID' 
  AND inbound = 1
  AND (protocol = 'udp' OR port = 5060);
EOF

echo "✅ Updated inbound gateways to TCP port 5070"
echo ""

echo "Final configuration:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, inbound, outbound FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' ORDER BY outbound DESC, inbound DESC;" 2>/dev/null

echo ""
echo "=========================================="
echo "Note on Twilio vs Exotel"
echo "=========================================="
echo ""
echo "Twilio uses: UDP port 5060 for signaling"
echo "Exotel uses: TCP port 5070 for signaling"
echo ""
echo "Different providers, different protocols. Both are correct for their"
echo "respective providers."
echo ""

