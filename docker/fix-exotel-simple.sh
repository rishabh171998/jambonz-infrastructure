#!/bin/bash
# Simple Exotel TCP/UDP setup (like Twilio) - No TLS complexity

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
echo "Exotel Simple Setup (TCP/UDP - Like Twilio)"
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

# Use TCP by default (more reliable than UDP, simpler than TLS)
PROTOCOL="tcp"
PORT=5070
FQDN="pstn.in4.exotel.com"

echo "Configuring: $FQDN:$PORT with protocol: $PROTOCOL"
echo "(This is the simple setup - no TLS complexity)"
echo ""

# Check current gateways
echo "Current gateways:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, inbound, outbound FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null
echo ""

# Find or create outbound gateway
OUTBOUND_GATEWAY_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_gateway_sid FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND (ipv4 = 'pstn.in2.exotel.com' OR ipv4 = 'pstn.in4.exotel.com') LIMIT 1;" 2>/dev/null)

if [ -z "$OUTBOUND_GATEWAY_SID" ]; then
  echo "Creating outbound gateway..."
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
  '$FQDN',
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
  echo "Updating existing gateway..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET 
  ipv4 = '$FQDN',
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
echo "Final configuration:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, inbound, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null

echo ""
echo "=========================================="
echo "✅ Done! Simple TCP Setup Complete"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  - FQDN: $FQDN"
echo "  - Port: $PORT"
echo "  - Protocol: $PROTOCOL (simple, like Twilio)"
echo ""
echo "📋 In the webapp, verify:"
echo "  1. Go to Carriers → Exotel → Outbound & Registration"
echo "  2. Check: Network address = $FQDN"
echo "  3. Check: Port = $PORT"
echo "  4. Check: Protocol = $PROTOCOL (NOT TLS)"
echo ""
echo "That's it! Simple and straightforward."
echo ""

