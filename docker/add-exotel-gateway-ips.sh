#!/bin/bash
# Add Exotel source IPs to gateways to fix "DID has not been provisioned" error

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
echo "Add Exotel Gateway IPs"
echo "=========================================="
echo ""

# Get Exotel carrier SID
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found!"
  exit 1
fi

echo "Exotel carrier SID: $CARRIER_SID"
echo ""

# Extract source IPs from sbc-inbound logs
echo "1. Finding Exotel source IPs from logs:"
echo "-------------------------------------------"
SOURCE_IPS=$(sudo docker compose logs --since 1h sbc-inbound 2>/dev/null | grep -oE '"source_address":"[0-9.]+"' | sed 's/.*"\([0-9.]*\)".*/\1/' | sort -u || echo "")

if [ -z "$SOURCE_IPS" ]; then
  echo "❌ Could not find source IPs in logs"
  echo ""
  echo "Known Exotel IPs (from your logs):"
  echo "  - 204.152.198.215"
  echo "  - 198.143.191.202"
  echo ""
  echo "Using these IPs..."
  SOURCE_IPS="204.152.198.215 198.143.191.202"
else
  echo "Found source IPs:"
  echo "$SOURCE_IPS"
fi
echo ""

echo "2. Current Exotel Gateways:"
echo "-------------------------------------------"
CURRENT_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, outbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
" 2>/dev/null || echo "")

if [ -n "$CURRENT_GATEWAYS" ] && ! echo "$CURRENT_GATEWAYS" | grep -q "Empty set"; then
  echo "$CURRENT_GATEWAYS"
else
  echo "No inbound gateways configured"
fi
echo ""

echo "3. Adding Missing Gateway IPs:"
echo "-------------------------------------------"
ADDED_COUNT=0
SKIPPED_COUNT=0

for IP in $SOURCE_IPS; do
  # Check if IP already exists
  EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT COUNT(*) 
  FROM sip_gateways 
  WHERE voip_carrier_sid = '$CARRIER_SID' 
  AND ipv4 = '$IP' 
  AND inbound = 1;
  " 2>/dev/null || echo "0")
  
  if [ "$EXISTS" -gt 0 ]; then
    echo "  ✅ IP $IP already exists"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
  else
    echo "  Adding IP: $IP"
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
  '$IP',
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
      ADDED_COUNT=$((ADDED_COUNT + 1))
    else
      echo "    ❌ Failed to add"
    fi
  fi
done
echo ""

echo "4. Summary:"
echo "-------------------------------------------"
echo "  Added: $ADDED_COUNT IPs"
echo "  Already existed: $SKIPPED_COUNT IPs"
echo ""

echo "5. Verify Phone Number Assignment:"
echo "-------------------------------------------"
PHONE_NUMBER="8064061518"
PHONE_CARRIER=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT voip_carrier_sid 
FROM phone_numbers 
WHERE number = '$PHONE_NUMBER';
" 2>/dev/null || echo "")

if [ -z "$PHONE_CARRIER" ]; then
  echo "❌ Phone number '$PHONE_NUMBER' not found in database!"
  echo ""
  echo "Fix: Add in webapp: Phone Numbers → Add → $PHONE_NUMBER"
elif [ "$PHONE_CARRIER" = "$CARRIER_SID" ]; then
  echo "✅ Phone number '$PHONE_NUMBER' is assigned to Exotel carrier"
else
  echo "⚠️  Phone number '$PHONE_NUMBER' is assigned to different carrier"
  echo "   Current carrier: $PHONE_CARRIER"
  echo "   Exotel carrier: $CARRIER_SID"
  echo ""
  echo "Fix: Update phone number to use Exotel carrier"
fi
echo ""

echo "6. Final Gateway Configuration:"
echo "-------------------------------------------"
FINAL_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, outbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1
ORDER BY ipv4;
" 2>/dev/null || echo "")

if [ -n "$FINAL_GATEWAYS" ]; then
  echo "$FINAL_GATEWAYS"
else
  echo "No gateways found"
fi
echo ""

echo "7. Restarting sbc-inbound:"
echo "-------------------------------------------"
$DOCKER_CMD restart sbc-inbound
echo "✅ sbc-inbound restarted"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Wait 30 seconds for sbc-inbound to restart"
echo "2. Make a test call from Exotel to $PHONE_NUMBER"
echo "3. Check logs:"
echo "   sudo docker compose logs -f sbc-inbound | grep '$PHONE_NUMBER'"
echo ""
echo "Expected result:"
echo "  ✅ 'inbound call accepted for routing'"
echo "  ✅ Call routes to application"
echo "  ❌ NOT 'rejecting call from carrier because DID has not been provisioned'"
echo ""

