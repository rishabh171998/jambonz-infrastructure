#!/bin/bash
# Fix 404 Not Found for Exotel calls

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
echo "Fixing Exotel 404 Not Found"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "Carrier SID: $CARRIER_SID"
echo ""

# Check phone numbers
echo "1. Phone Numbers Configured:"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, voip_carrier_sid, application_sid FROM phone_numbers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
echo "$PHONE_NUMBERS"
echo ""

# Check what number Exotel is calling
echo "2. From the logs, Exotel is sending:"
echo "   To: <sip:1219300017707497486@15.207.113.122>"
echo "   This looks like an Exotel internal ID, not a phone number"
echo ""

# Check carrier application routing
echo "3. Carrier Application Routing:"
CARRIER_APP=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT application_sid FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null | grep -v "application_sid" || echo "  (none)")
if [ -n "$CARRIER_APP" ] && [ "$CARRIER_APP" != "  (none)" ] && [ "$CARRIER_APP" != "NULL" ]; then
  echo "   ✅ Carrier has application_sid: $CARRIER_APP"
else
  echo "   ❌ Carrier does NOT have application_sid configured"
  echo "   This is why you're getting 404 - no application to route to"
fi
echo ""

# Check phone number application
echo "4. Phone Number Application Routing:"
PHONE_APP=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE voip_carrier_sid = '$CARRIER_SID' LIMIT 1;" 2>/dev/null | tail -1)
if [ -n "$PHONE_APP" ]; then
  echo "   Phone number routing: $PHONE_APP"
else
  echo "   ❌ No phone numbers found"
fi
echo ""

echo "=========================================="
echo "The Problem"
echo "=========================================="
echo ""
echo "The 404 Not Found means:"
echo "  ✅ Exotel CAN reach Jambonz (connectivity works!)"
echo "  ✅ TCP/UDP is working"
echo "  ❌ But Jambonz can't find where to route the call"
echo ""
echo "This happens when:"
echo "  1. Phone number not configured in Jambonz"
echo "  2. Phone number doesn't have an application assigned"
echo "  3. Carrier doesn't have default application"
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "Option 1: Assign application to phone number"
echo "  - Go to webapp: Phone Numbers → Edit number"
echo "  - Assign an Application"
echo ""
echo "Option 2: Set default application on carrier"
echo "  - Go to webapp: Carriers → Exotel → General"
echo "  - Set 'Application for incoming calls'"
echo ""
echo "Option 3: Check Exotel destination URI"
echo "  - In Exotel dashboard, check the destination URI"
echo "  - Should be: sip:graineone.sip.graine.ai:5060;transport=tcp"
echo "  - Or: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "  - The 'To' header should match your phone number format"
echo ""

