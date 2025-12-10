#!/bin/bash
# Final fix for Exotel - Add source IP and verify configuration

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Final Exotel Fix"
echo "=========================================="
echo ""

echo "Current Status:"
echo "  ✅ Phone number IS in Request URI: 8064061518"
echo "  ❌ Still using FQDN: graineone.sip.graine.ai (causes SIP realm matching)"
echo "  ❌ Source IP 129.154.231.198 needs to be in gateways"
echo ""

# Get Exotel carrier SID
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found!"
  exit 1
fi

echo "1. Adding Source IP to Gateways:"
echo "-------------------------------------------"
SOURCE_IP="129.154.231.198"

EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT COUNT(*) 
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' 
AND ipv4 = '$SOURCE_IP' 
AND inbound = 1;
" 2>/dev/null || echo "0")

if [ "$EXISTS" -gt 0 ]; then
  echo "  ✅ IP $SOURCE_IP already exists"
else
  echo "  Adding IP: $SOURCE_IP"
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
  netmask
) VALUES (
  UUID(),
  '$SOURCE_IP',
  5060,
  'udp',
  1,
  0,
  1,
  '$CARRIER_SID',
  32
);
EOF
  if [ $? -eq 0 ]; then
    echo "    ✅ Successfully added"
  else
    echo "    ❌ Failed to add"
  fi
fi
echo ""

echo "2. All Exotel Gateway IPs:"
echo "-------------------------------------------"
ALL_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1
ORDER BY ipv4;
" 2>/dev/null || echo "")

if [ -n "$ALL_GATEWAYS" ]; then
  echo "$ALL_GATEWAYS"
else
  echo "No gateways found"
fi
echo ""

echo "3. Restarting sbc-inbound:"
echo "-------------------------------------------"
$DOCKER_CMD restart sbc-inbound
echo "✅ sbc-inbound restarted"
echo ""

echo "=========================================="
echo "CRITICAL: Update Exotel Destination URI"
echo "=========================================="
echo ""
echo "The phone number is now in the Request URI (good!),"
echo "but the FQDN 'graineone.sip.graine.ai' is causing"
echo "SIP realm matching (calls treated as user calls)."
echo ""
echo "Update Exotel Destination URI:"
echo ""
echo "  Current:"
echo "    sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "  Change to:"
echo "    sip:8064061518@15.207.113.122:5060;transport=tcp"
echo ""
echo "This will:"
echo "  ✅ Keep phone number in Request URI"
echo "  ✅ Use IP instead of FQDN (no SIP realm matching)"
echo "  ✅ Include port (as required by Exotel)"
echo ""
echo "After updating Exotel:"
echo "  1. Wait 1-2 minutes"
echo "  2. Make a test call"
echo "  3. Check logs:"
echo "     sudo docker compose logs -f sbc-inbound | grep '8064061518'"
echo ""
echo "Expected:"
echo "  ✅ 'inbound call accepted for routing' (phone number call)"
echo "  ❌ NOT 'incoming user call' (SIP registration)"
echo ""

