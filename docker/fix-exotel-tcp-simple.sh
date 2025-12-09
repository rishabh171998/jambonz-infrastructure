#!/bin/bash
# Simple Exotel TCP/UDP configuration (like Twilio)

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
echo "Exotel TCP/UDP Configuration (Simple)"
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

# Ask user for protocol preference
echo "Which protocol do you want to use?"
echo "1) TCP (recommended - more reliable)"
echo "2) UDP (faster, but less reliable)"
read -p "Enter choice [1 or 2]: " PROTOCOL_CHOICE

if [ "$PROTOCOL_CHOICE" = "2" ]; then
  PROTOCOL="udp"
  PORT=5060
else
  PROTOCOL="tcp"
  PORT=5070
fi

echo ""
echo "Using protocol: $PROTOCOL on port: $PORT"
echo ""

# Check current gateways
echo "Current gateways:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null
echo ""

# Find or create outbound gateway
OUTBOUND_GATEWAY_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_gateway_sid FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND (ipv4 = 'pstn.in2.exotel.com' OR ipv4 = 'pstn.in4.exotel.com') LIMIT 1;" 2>/dev/null)

# Get the current FQDN if gateway exists
CURRENT_FQDN=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT ipv4 FROM sip_gateways WHERE sip_gateway_sid = '$OUTBOUND_GATEWAY_SID' LIMIT 1;" 2>/dev/null || echo "pstn.in4.exotel.com")

if [ -z "$OUTBOUND_GATEWAY_SID" ]; then
  echo "Creating outbound gateway ($CURRENT_FQDN:$PORT)..."
  OUTBOUND_GATEWAY_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO sip_gateways (
  sip_gateway_sid,
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active,
  voip_carrier_sid,
  netmask,
  send_options_ping,
  use_sips_scheme,
  pad_crypto
) VALUES (
  '$OUTBOUND_GATEWAY_SID',
  '$CURRENT_FQDN',
  $PORT,
  '$PROTOCOL',
  0,
  1,
  1,
  '$CARRIER_SID',
  32,
  0,
  0,
  0
);
EOF
  echo "✅ Created outbound gateway"
else
  echo "Updating existing gateway to $PROTOCOL on port $PORT..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET 
  port = $PORT,
  protocol = '$PROTOCOL',
  inbound = 0,
  outbound = 1,
  is_active = 1
WHERE sip_gateway_sid = '$OUTBOUND_GATEWAY_SID';
EOF
  echo "✅ Updated gateway to $PROTOCOL on port $PORT"
fi

echo ""
echo "Final gateway configuration:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' ORDER BY outbound DESC, inbound DESC;" 2>/dev/null

echo ""
echo "=========================================="
echo "Configuration Complete!"
echo "=========================================="
echo ""
echo "✅ Outbound Gateway:"
echo "   - FQDN: $CURRENT_FQDN"
echo "   - Port: $PORT"
echo "   - Protocol: $PROTOCOL"
echo "   - Direction: Outbound only"
echo ""
echo "📋 Next Steps:"
echo "   1. In Exotel dashboard, whitelist your Jambonz public IP"
echo "   2. Test outbound calls"
echo "   3. For inbound calls, configure phone numbers in Exotel"
echo ""

