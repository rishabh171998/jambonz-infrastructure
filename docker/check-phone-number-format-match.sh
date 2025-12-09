#!/bin/bash
# Check if phone number format matches between Exotel and Jambonz database

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
echo "Phone Number Format Matching Check"
echo "=========================================="
echo ""

echo "1. Exotel is sending:"
echo "-------------------------------------------"
echo "  sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "  (Phone number: 8064061518)"
echo ""

echo "2. Phone numbers in Jambonz database:"
echo "-------------------------------------------"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number, application_sid 
FROM phone_numbers 
WHERE number LIKE '%8064061518%' OR number LIKE '%08064061518%' OR number LIKE '%918064061518%';
" 2>/dev/null || echo "")

if [ -z "$PHONE_NUMBERS" ] || echo "$PHONE_NUMBERS" | grep -q "Empty set"; then
  echo "❌ No matching phone numbers found!"
  echo ""
  echo "Exotel sends: 8064061518"
  echo "Database has: (none found)"
  echo ""
  echo "Possible formats to check:"
  echo "  - 8064061518 (what Exotel sends)"
  echo "  - 08064061518 (with leading 0)"
  echo "  - 918064061518 (with country code)"
  echo "  - +918064061518 (E.164 format)"
else
  echo "$PHONE_NUMBERS"
  echo ""
  
  # Check each format
  FORMAT_8064061518=$(echo "$PHONE_NUMBERS" | grep -q "8064061518" && echo "✅" || echo "❌")
  FORMAT_08064061518=$(echo "$PHONE_NUMBERS" | grep -q "08064061518" && echo "✅" || echo "❌")
  FORMAT_918064061518=$(echo "$PHONE_NUMBERS" | grep -q "918064061518" && echo "✅" || echo "❌")
  
  echo "Format matching:"
  echo "  8064061518 (Exotel format): $FORMAT_8064061518"
  echo "  08064061518 (with 0): $FORMAT_08064061518"
  echo "  918064061518 (with country): $FORMAT_918064061518"
  echo ""
  
  if [ "$FORMAT_8064061518" = "❌" ]; then
    echo "⚠️  Format mismatch! Exotel sends '8064061518' but database has different format"
    echo ""
    echo "Solution: Add phone number in the format Exotel sends:"
    echo "  Number: 8064061518"
    echo "  (or update Exotel to send a format that matches database)"
  fi
fi
echo ""

echo "3. Recent call responses:"
echo "-------------------------------------------"
RESPONSES=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep -E "(8064061518|404|200 OK|BYE|CANCEL)" | tail -20 || echo "")

if [ -n "$RESPONSES" ]; then
  echo "$RESPONSES" | sed 's/^drachtio-sbc-1  | //' | head -15
  
  NOT_FOUND=$(echo "$RESPONSES" | grep -c "404 Not Found" || echo "0")
  OK=$(echo "$RESPONSES" | grep -c "200 OK" || echo "0")
  BYE=$(echo "$RESPONSES" | grep -c "BYE" || echo "0")
  
  echo ""
  echo "Summary:"
  echo "  404 Not Found: $NOT_FOUND"
  echo "  200 OK: $OK"
  echo "  BYE (disconnect): $BYE"
else
  echo "No recent responses found"
fi
echo ""

echo "4. sbc-inbound logs (routing):"
echo "-------------------------------------------"
SBC_INBOUND=$(sudo docker compose logs --since 10m sbc-inbound 2>/dev/null | grep -iE "(8064061518|phone|routing|application)" | tail -10 || echo "")

if [ -n "$SBC_INBOUND" ]; then
  echo "$SBC_INBOUND" | sed 's/^sbc-inbound-1  | //'
else
  echo "No relevant sbc-inbound logs found"
fi
echo ""

echo "=========================================="
echo "Diagnosis"
echo "=========================================="
echo ""

if echo "$PHONE_NUMBERS" | grep -q "8064061518"; then
  echo "✅ Phone number format matches!"
  echo ""
  echo "If calls still disconnect, check:"
  echo "  1. Application is configured correctly"
  echo "  2. RTP/audio issues (check rtpengine logs)"
  echo "  3. Application webhook issues"
  echo "  4. Check sbc-inbound logs for routing errors"
else
  echo "❌ Phone number format mismatch!"
  echo ""
  echo "Fix: Add phone number in format Exotel sends:"
  echo "  1. Go to Jambonz webapp: Phone Numbers → Add Phone Number"
  echo "  2. Number: 8064061518"
  echo "  3. Carrier: Exotel"
  echo "  4. Application: Select your application"
  echo "  5. Save"
fi
echo ""

