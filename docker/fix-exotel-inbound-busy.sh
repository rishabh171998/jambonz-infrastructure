#!/bin/bash
# Fix Exotel inbound call "busy" issue

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
echo "Fixing Exotel Inbound 'Busy' Issue"
echo "=========================================="
echo ""

TRUNK_ID="trmum1c8b50c05af3fbe62c519c9"
EXOPHONE="08064061518"

echo "Call Details:"
echo "  From: 07683000178"
echo "  To: $EXOPHONE"
echo "  Trunk ID: $TRUNK_ID"
echo "  Status: Busy (call not accepted)"
echo ""

echo "=== Issue Analysis ==="
echo ""
echo "The call was routed to: sip:$TRUNK_ID"
echo "This means Exotel is trying to send the call to your SIP trunk,"
echo "but Jambonz is either:"
echo "  1. Not receiving the INVITE"
echo "  2. Rejecting the INVITE"
echo "  3. Not routing to an application"
echo ""

echo "=== Checking Carrier Configuration ==="
echo ""

# Find carrier by trunk ID or name
CARRIER_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null
SELECT 
  voip_carrier_sid,
  name,
  is_active,
  application_sid,
  account_sid
FROM voip_carriers 
WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%'
LIMIT 1;
EOF
)

if [ -z "$CARRIER_INFO" ]; then
  echo "❌ No Exotel carrier found!"
  echo ""
  echo "Please create a carrier in Jambonz webapp first."
  exit 1
fi

CARRIER_SID=$(echo "$CARRIER_INFO" | awk '{print $1}')
CARRIER_NAME=$(echo "$CARRIER_INFO" | awk '{print $2}')
IS_ACTIVE=$(echo "$CARRIER_INFO" | awk '{print $3}')
APP_SID=$(echo "$CARRIER_INFO" | awk '{print $4}')
ACCOUNT_SID=$(echo "$CARRIER_INFO" | awk '{print $5}')

echo "Carrier: $CARRIER_NAME (SID: $CARRIER_SID)"
echo "Active: $IS_ACTIVE"
echo "Application SID: ${APP_SID:-NOT SET}"
echo "Account SID: ${ACCOUNT_SID:-NOT SET}"
echo ""

if [ "$IS_ACTIVE" != "1" ]; then
  echo "⚠️  WARNING: Carrier is not active!"
  echo "   Fix: Go to webapp and enable the carrier"
fi

if [ -z "$APP_SID" ]; then
  echo "⚠️  WARNING: No application associated with carrier!"
  echo "   This is likely the cause of the 'busy' issue."
  echo ""
  echo "   Fix options:"
  echo "   1. Associate an application with the carrier"
  echo "   2. Set up call routing for the Exophone number"
fi

echo ""
echo "=== Checking SIP Gateway Configuration ==="
echo ""

GATEWAY_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null
SELECT 
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID';
EOF
)

if [ -z "$GATEWAY_INFO" ]; then
  echo "❌ No SIP gateway configured for this carrier!"
  echo "   Fix: Add a SIP gateway in the webapp"
else
  echo "$GATEWAY_INFO"
  
  # Check if gateway is correct
  if echo "$GATEWAY_INFO" | grep -q "pstn.in2.exotel.com"; then
    echo "✅ Gateway address is correct"
  else
    echo "⚠️  WARNING: Gateway address might be wrong"
    echo "   Should be: pstn.in2.exotel.com"
  fi
  
  if echo "$GATEWAY_INFO" | grep -q "tcp"; then
    echo "✅ Protocol is TCP (correct)"
  else
    echo "⚠️  WARNING: Protocol should be TCP, not UDP"
  fi
  
  if echo "$GATEWAY_INFO" | grep -q "inbound.*1"; then
    echo "✅ Inbound is enabled"
  else
    echo "⚠️  WARNING: Inbound is not enabled!"
  fi
fi

echo ""
echo "=== Checking Phone Number Configuration ==="
echo ""

PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null
SELECT 
  phone_number_sid,
  number,
  voip_carrier_sid,
  account_sid,
  application_sid
FROM phone_numbers 
WHERE number = '$EXOPHONE' OR number = '+91$EXOPHONE';
EOF
)

if [ -z "$PHONE_INFO" ]; then
  echo "⚠️  WARNING: Phone number $EXOPHONE not found in database!"
  echo "   This might be the issue - Jambonz doesn't know how to route this number"
  echo ""
  echo "   Fix: Add the phone number in Jambonz webapp:"
  echo "   1. Go to Phone Numbers"
  echo "   2. Add number: $EXOPHONE"
  echo "   3. Associate with your carrier"
  echo "   4. Associate with an application"
else
  echo "Phone number found:"
  echo "$PHONE_INFO"
  PHONE_APP_SID=$(echo "$PHONE_INFO" | awk '{print $5}')
  if [ -z "$PHONE_APP_SID" ]; then
    echo "⚠️  WARNING: Phone number has no application associated!"
    echo "   Fix: Associate an application with this phone number"
  fi
fi

echo ""
echo "=== Checking Recent SBC Logs ==="
echo ""

echo "Looking for INVITE from Exotel (last 50 lines):"
$DOCKER_CMD logs sbc-inbound --tail 50 2>/dev/null | grep -iE "invite|exotel|$EXOPHONE|182.76|122.15" | tail -10 || echo "  No relevant logs found"

echo ""
echo "=== Checking Feature Server Logs ==="
echo ""

echo "Looking for call routing attempts (last 50 lines):"
$DOCKER_CMD logs feature-server --tail 50 2>/dev/null | grep -iE "$EXOPHONE|$EXOPHONE|carrier|routing|application" | tail -10 || echo "  No relevant logs found"

echo ""
echo "=== Most Likely Issues ==="
echo ""

echo "1. ❌ Phone number not configured in Jambonz"
echo "   → Add $EXOPHONE as a phone number"
echo "   → Associate with your carrier"
echo "   → Associate with an application"
echo ""

echo "2. ❌ No application associated"
echo "   → Either associate app with carrier OR"
echo "   → Associate app with phone number"
echo ""

echo "3. ❌ SIP gateway not configured correctly"
echo "   → Check gateway address is pstn.in2.exotel.com"
echo "   → Check protocol is TCP"
echo "   → Check inbound is enabled"
echo ""

echo "=== Quick Fix Steps ==="
echo ""

echo "1. Go to Jambonz webapp → Phone Numbers"
echo "2. Click 'Add phone number'"
echo "3. Enter: $EXOPHONE"
echo "4. Select your Exotel carrier"
echo "5. Select an application to handle calls"
echo "6. Save"
echo ""

echo "OR"
echo ""

echo "1. Go to Jambonz webapp → Carriers"
echo "2. Edit your Exotel carrier"
echo "3. In 'General' tab, set 'Application' field"
echo "4. Select an application"
echo "5. Save"
echo ""

echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="

