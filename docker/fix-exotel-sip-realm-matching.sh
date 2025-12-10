#!/bin/bash
# Fix Exotel calls being treated as user calls instead of phone number calls

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
echo "Fix Exotel SIP Realm Matching Issue"
echo "=========================================="
echo ""

echo "Problem Identified:"
echo "  - Source IP: 129.154.231.198"
echo "  - Domain: graineone.sip.graine.ai (matches SIP realm)"
echo "  - Result: Calls treated as 'user calls' instead of phone number calls"
echo ""

# Get Exotel carrier SID
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found!"
  exit 1
fi

echo "Exotel carrier SID: $CARRIER_SID"
echo ""

echo "1. Adding Source IP to Gateways:"
echo "-------------------------------------------"
SOURCE_IP="129.154.231.198"

# Check if IP exists
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

echo "2. Checking SIP Realms:"
echo "-------------------------------------------"
SIP_REALMS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT account_sid, sip_realm 
FROM accounts 
WHERE sip_realm = 'graineone.sip.graine.ai' OR sip_realm LIKE '%graineone%';
" 2>/dev/null || echo "")

if [ -n "$SIP_REALMS" ] && ! echo "$SIP_REALMS" | grep -q "Empty set"; then
  echo "⚠️  Found SIP realm matching 'graineone.sip.graine.ai':"
  echo "$SIP_REALMS"
  echo ""
  echo "This is why calls are treated as user calls!"
  echo ""
  echo "Solution: Update Exotel Destination URI to use IP instead of FQDN"
else
  echo "No matching SIP realm found"
fi
echo ""

echo "3. Phone Number Configuration:"
echo "-------------------------------------------"
PHONE_NUMBER="8064061518"
PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number, voip_carrier_sid, application_sid
FROM phone_numbers 
WHERE number = '$PHONE_NUMBER';
" 2>/dev/null || echo "")

if [ -n "$PHONE_INFO" ] && ! echo "$PHONE_INFO" | grep -q "Empty set"; then
  echo "$PHONE_INFO"
  
  PHONE_CARRIER=$(echo "$PHONE_INFO" | grep -v "voip_carrier_sid" | awk '{print $2}' | head -1 || echo "")
  if [ "$PHONE_CARRIER" = "$CARRIER_SID" ]; then
    echo ""
    echo "✅ Phone number is assigned to Exotel carrier"
  else
    echo ""
    echo "❌ Phone number carrier mismatch"
  fi
else
  echo "❌ Phone number not found"
fi
echo ""

echo "4. Restarting sbc-inbound:"
echo "-------------------------------------------"
$DOCKER_CMD restart sbc-inbound
echo "✅ sbc-inbound restarted"
echo ""

echo "=========================================="
echo "CRITICAL FIX REQUIRED IN EXOTEL"
echo "=========================================="
echo ""
echo "The Request URI domain 'graineone.sip.graine.ai' is matching a SIP realm,"
echo "causing calls to be treated as user calls instead of phone number calls."
echo ""
echo "Update Exotel Destination URI:"
echo ""
echo "  Current (WRONG):"
echo "    sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "  Change to (CORRECT):"
echo "    sip:8064061518@15.207.113.122"
echo ""
echo "  Or:"
echo "    sip:8064061518@15.207.113.122:5060;transport=tcp"
echo ""
echo "Using the IP address instead of FQDN will prevent SIP realm matching."
echo ""

echo "=========================================="
echo "After Fixing Exotel Destination URI"
echo "=========================================="
echo ""
echo "1. Update Destination URI in Exotel dashboard (use IP instead of FQDN)"
echo "2. Wait 1-2 minutes for changes to propagate"
echo "3. Make a test call"
echo "4. Check logs:"
echo "   sudo docker compose logs -f sbc-inbound | grep '8064061518'"
echo ""
echo "Expected result:"
echo "  ✅ 'inbound call accepted for routing' (phone number call)"
echo "  ❌ NOT 'incoming user call' (SIP registration)"
echo ""

