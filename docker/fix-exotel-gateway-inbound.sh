#!/bin/bash
# Enable inbound on Exotel SIP gateway

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
echo "Fixing Exotel SIP Gateway Inbound"
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

# Find the signaling gateway (pstn.in2.exotel.com)
GATEWAY_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_gateway_sid FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND ipv4 = 'pstn.in2.exotel.com' AND port = 5070 LIMIT 1;" 2>/dev/null)

if [ -z "$GATEWAY_SID" ]; then
  echo "❌ SIP gateway pstn.in2.exotel.com:5070 not found"
  echo ""
  echo "Checking all gateways for this carrier:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT sip_gateway_sid, ipv4, port, protocol, inbound, outbound FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null
  exit 1
fi

echo "Found gateway SID: $GATEWAY_SID"
echo ""

# Check current inbound status
CURRENT_INBOUND=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT inbound FROM sip_gateways WHERE sip_gateway_sid = '$GATEWAY_SID';" 2>/dev/null)
CURRENT_OUTBOUND=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT outbound FROM sip_gateways WHERE sip_gateway_sid = '$GATEWAY_SID';" 2>/dev/null)

echo "Current status:"
echo "  Inbound: $CURRENT_INBOUND"
echo "  Outbound: $CURRENT_OUTBOUND"
echo ""

if [ "$CURRENT_INBOUND" = "1" ]; then
  echo "✅ Inbound is already enabled on this gateway"
else
  echo "Enabling inbound on gateway..."
  echo "  (Gateway will have both inbound: 1 and outbound: $CURRENT_OUTBOUND)"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET inbound = 1 
WHERE sip_gateway_sid = '$GATEWAY_SID';
EOF

  if [ $? -eq 0 ]; then
    echo "✅ Successfully enabled inbound on pstn.in2.exotel.com:5070"
    echo ""
    echo "⚠️  IMPORTANT: The webapp separates gateways into 'Inbound' and 'Outbound' tabs."
    echo "   After this fix, the gateway will appear in BOTH tabs in the webapp."
    echo "   This is correct - it needs to be in both for Exotel to work."
  else
    echo "❌ Failed to enable inbound"
    exit 1
  fi
fi

echo ""
echo "Verifying gateway configuration:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
SELECT 
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active
FROM sip_gateways 
WHERE sip_gateway_sid = '$GATEWAY_SID';
EOF

echo ""
echo "=========================================="
echo "Gateway Fixed!"
echo "=========================================="
echo ""
echo "✅ Inbound is now enabled on pstn.in2.exotel.com:5070"
echo ""
echo "The gateway should now accept incoming calls from Exotel."
echo ""
echo "Note: IP whitelisting in Exotel is optional but recommended"
echo "for security. If you want to enable it, add your Jambonz"
echo "public IP in Exotel Dashboard → Trunk Settings → Whitelisted IPs"
echo ""

