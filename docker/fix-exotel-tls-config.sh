#!/bin/bash
# Fix Exotel TLS configuration for proper inbound/outbound setup

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
echo "Fixing Exotel TLS Configuration"
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

# Check current gateways
echo "Current gateways:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null
echo ""

# Find or create outbound TLS gateway (pstn.in2.exotel.com or pstn.in4.exotel.com on port 443)
OUTBOUND_GATEWAY_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_gateway_sid FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND (ipv4 = 'pstn.in2.exotel.com' OR ipv4 = 'pstn.in4.exotel.com') AND (port = 443 OR port = 5070) LIMIT 1;" 2>/dev/null)

# Get the current FQDN if gateway exists
CURRENT_FQDN=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT ipv4 FROM sip_gateways WHERE sip_gateway_sid = '$OUTBOUND_GATEWAY_SID' LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$OUTBOUND_GATEWAY_SID" ]; then
  echo "Creating outbound TLS gateway (pstn.in4.exotel.com:443)..."
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
  'pstn.in4.exotel.com',
  443,
  'tls',
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
  echo "✅ Created outbound TLS gateway"
else
  echo "Updating existing gateway to TLS on port 443..."
  # Preserve the existing FQDN (pstn.in2.exotel.com or pstn.in4.exotel.com)
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET 
  port = 443,
  protocol = 'tls',
  inbound = 0,
  outbound = 1,
  is_active = 1
WHERE sip_gateway_sid = '$OUTBOUND_GATEWAY_SID';
EOF
  echo "✅ Updated gateway to TLS on port 443 (keeping FQDN: $CURRENT_FQDN)"
fi

echo ""

# Remove FQDN from inbound gateways (webapp doesn't allow FQDNs in inbound)
echo "Checking for FQDNs in inbound gateways..."
FQDN_INBOUND=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1 AND (ipv4 LIKE '%.%' AND ipv4 NOT REGEXP '^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$');" 2>/dev/null)

if [ "$FQDN_INBOUND" -gt 0 ]; then
  echo "⚠️  Found FQDN in inbound gateways. Removing..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET inbound = 0 
WHERE voip_carrier_sid = '$CARRIER_SID' 
  AND inbound = 1 
  AND ipv4 NOT REGEXP '^[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}$';
EOF
  echo "✅ Removed FQDN from inbound gateways"
  echo ""
  echo "⚠️  IMPORTANT: For inbound calls, you need to add Exotel's signaling server IP addresses"
  echo "   (not FQDNs) to the 'Allowed IP Addresses' section in the webapp."
  echo ""
  echo "   Contact Exotel support to get the actual IP addresses of:"
  echo "   - pstn.in2.exotel.com (Mumbai DC)"
  echo "   - pstn.in4.exotel.com (Mumbai Cloud)"
  echo ""
  echo "   Or use the media IPs if they're the same as signaling:"
  echo "   - 182.76.143.61, 122.15.8.184 (Mumbai DC)"
  echo "   - 14.194.10.247, 61.246.82.75 (KA DC)"
fi

echo ""
echo "Final gateway configuration:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' ORDER BY outbound DESC, inbound DESC;" 2>/dev/null

echo ""
echo "=========================================="
echo "Configuration Summary"
echo "=========================================="
echo ""
echo "✅ Outbound Gateway:"
echo "   - FQDN: pstn.in2.exotel.com or pstn.in4.exotel.com (Mumbai Cloud)"
echo "   - Port: 443 (TLS) - FIXED from 5070"
echo "   - Protocol: tls"
echo "   - Direction: Outbound only"
echo ""
echo "📋 Next Steps:"
echo "   1. In the webapp, go to Carriers → Exotel → Inbound tab"
echo "   2. Remove 'pstn.in2.exotel.com:5070' from 'Allowed IP Addresses'"
echo "   3. Add Exotel's signaling server IP addresses (contact Exotel for exact IPs)"
echo "   4. Keep the media IPs (182.76.143.61, 122.15.8.184, etc.) if they're correct"
echo ""
echo "⚠️  Note: The webapp doesn't allow FQDNs in the Inbound section."
echo "   You must use actual IP addresses for inbound SIP signaling whitelisting."
echo ""

