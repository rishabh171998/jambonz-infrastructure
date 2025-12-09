#!/bin/bash
# Verify phone number configuration in Jambonz

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
echo "Phone Number Configuration Check"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "Carrier SID: $CARRIER_SID"
echo ""

echo "1. Phone Numbers for Exotel Carrier:"
echo "-------------------------------------------"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  phone_number_sid,
  number,
  application_sid,
  account_sid
FROM phone_numbers 
WHERE voip_carrier_sid = '$CARRIER_SID'
ORDER BY number;
" 2>/dev/null)

if [ -z "$PHONE_NUMBERS" ] || echo "$PHONE_NUMBERS" | grep -q "Empty set"; then
  echo "❌ No phone numbers configured for Exotel carrier"
  echo ""
  echo "You need to add phone numbers in the webapp:"
  echo "  1. Go to: Phone Numbers → Add Phone Number"
  echo "  2. Number: +918064061518 (or 08064061518)"
  echo "  3. Carrier: Select Exotel"
  echo "  4. Application: Select your application"
else
  echo "$PHONE_NUMBERS"
  echo ""
  
  # Check if application is assigned
  echo "2. Application Assignment:"
  echo "-------------------------------------------"
  while IFS=$'\t' read -r phone_sid number app_sid account_sid; do
    if [ "$phone_sid" = "phone_number_sid" ]; then
      continue
    fi
    if [ -z "$app_sid" ] || [ "$app_sid" = "NULL" ]; then
      echo "❌ $number: No application assigned"
    else
      APP_NAME=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT name FROM applications WHERE application_sid = '$app_sid';" 2>/dev/null || echo "Unknown")
      echo "✅ $number → Application: $APP_NAME ($app_sid)"
    fi
  done <<< "$PHONE_NUMBERS"
fi
echo ""

echo "3. Expected Request URI Formats:"
echo "-------------------------------------------"
echo "Jambonz will accept any of these formats:"
echo ""
echo "  ✅ sip:+918064061518@15.207.113.122"
echo "  ✅ sip:918064061518@15.207.113.122"
echo "  ✅ sip:08064061518@15.207.113.122"
echo ""
echo "❌ Will NOT work:"
echo "  ❌ sip:27270013103585148@15.207.113.122 (Exotel internal ID)"
echo ""

echo "4. Recent INVITEs from Exotel:"
echo "-------------------------------------------"
RECENT_INVITES=$($DOCKER_CMD logs --since 5m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -5 | sed 's/^drachtio-sbc-1  | //' || echo "No recent INVITEs")

if [ -n "$RECENT_INVITES" ]; then
  echo "$RECENT_INVITES" | while IFS= read -r line; do
    if echo "$line" | grep -qE "(918064061518|08064061518)"; then
      echo "✅ $line (contains phone number)"
    else
      echo "❌ $line (Exotel internal ID - needs fix)"
    fi
  done
else
  echo "No recent INVITEs found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if echo "$PHONE_NUMBERS" | grep -q "918064061518\|08064061518"; then
  echo "✅ Phone numbers are configured in Jambonz"
  echo ""
  echo "❌ Issue: Exotel is sending internal IDs instead of phone numbers"
  echo ""
  echo "🔧 Fix: Update Exotel Destination URI to include phone number:"
  echo "   sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
else
  echo "❌ Phone numbers are NOT configured in Jambonz"
  echo ""
  echo "🔧 Fix: Add phone numbers in webapp first"
fi
echo ""

