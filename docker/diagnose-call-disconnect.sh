#!/bin/bash
# Diagnose why Exotel calls are disconnecting

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
echo "Call Disconnect Diagnosis"
echo "=========================================="
echo ""

echo "1. Phone Number Format Check:"
echo "-------------------------------------------"
echo "Exotel sends: 8064061518"
echo ""

PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number, application_sid, voip_carrier_sid
FROM phone_numbers 
WHERE number LIKE '%8064061518%' OR number LIKE '%08064061518%' OR number LIKE '%918064061518%';
" 2>/dev/null || echo "")

if [ -z "$PHONE_NUMBERS" ] || echo "$PHONE_NUMBERS" | grep -q "Empty set"; then
  echo "❌ Phone number NOT found in database!"
  echo ""
  echo "Fix: Add phone number '8064061518' in Jambonz webapp"
else
  echo "✅ Phone numbers in database:"
  echo "$PHONE_NUMBERS"
  echo ""
  
  if echo "$PHONE_NUMBERS" | grep -q "^8064061518"; then
    echo "✅ Format matches! (8064061518)"
  else
    echo "⚠️  Format mismatch - Exotel sends '8064061518' but database has different format"
    echo ""
    echo "Solution: Add phone number as '8064061518' in webapp"
  fi
fi
echo ""

echo "2. Recent Call Flow (last 5 minutes):"
echo "-------------------------------------------"
RECENT_CALLS=$(sudo docker compose logs --since 5m drachtio-sbc 2>/dev/null | grep -E "(8064061518|INVITE|100 Trying|180 Ringing|200 OK|404|BYE|CANCEL)" | tail -30 || echo "")

if [ -n "$RECENT_CALLS" ]; then
  echo "$RECENT_CALLS" | sed 's/^drachtio-sbc-1  | //' | head -25
  
  # Count responses
  TRYING=$(echo "$RECENT_CALLS" | grep -c "100 Trying" || echo "0")
  RINGING=$(echo "$RECENT_CALLS" | grep -c "180 Ringing" || echo "0")
  OK=$(echo "$RECENT_CALLS" | grep -c "200 OK" || echo "0")
  NOT_FOUND=$(echo "$RECENT_CALLS" | grep -c "404 Not Found" || echo "0")
  BYE=$(echo "$RECENT_CALLS" | grep -c "BYE" || echo "0")
  CANCEL=$(echo "$RECENT_CALLS" | grep -c "CANCEL" || echo "0")
  
  echo ""
  echo "Call flow summary:"
  echo "  100 Trying: $TRYING"
  echo "  180 Ringing: $RINGING"
  echo "  200 OK: $OK"
  echo "  404 Not Found: $NOT_FOUND"
  echo "  BYE (hangup): $BYE"
  echo "  CANCEL: $CANCEL"
  
  if [ "$NOT_FOUND" -gt 0 ]; then
    echo ""
    echo "❌ 404 Not Found - Phone number not found or routing failed"
  elif [ "$OK" -gt 0 ] && [ "$BYE" -gt 0 ]; then
    echo ""
    echo "✅ Call connected (200 OK) but then disconnected (BYE)"
    echo "   This suggests audio/RTP or application issue"
  elif [ "$OK" -eq 0 ] && [ "$BYE" -gt 0 ]; then
    echo ""
    echo "⚠️  Call disconnected before connecting (no 200 OK)"
  fi
else
  echo "No recent calls found. Make a test call first."
fi
echo ""

echo "3. sbc-inbound Routing Logs:"
echo "-------------------------------------------"
SBC_LOGS=$(sudo docker compose logs --since 5m sbc-inbound 2>/dev/null | grep -iE "(8064061518|routing|application|error|fail)" | tail -20 || echo "")

if [ -n "$SBC_LOGS" ]; then
  echo "$SBC_LOGS" | sed 's/^sbc-inbound-1  | //'
else
  echo "No relevant sbc-inbound logs found"
fi
echo ""

echo "4. Application Configuration:"
echo "-------------------------------------------"
if echo "$PHONE_NUMBERS" | grep -q "application_sid"; then
  APP_SID=$(echo "$PHONE_NUMBERS" | grep -v "application_sid" | head -1 | awk '{print $2}' || echo "")
  if [ -n "$APP_SID" ] && [ "$APP_SID" != "NULL" ]; then
    APP_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
    SELECT name, call_hook_sid, app_json IS NOT NULL as has_app_json
    FROM applications 
    WHERE application_sid = '$APP_SID';
    " 2>/dev/null | grep -v "name" || echo "")
    
    if [ -n "$APP_INFO" ]; then
      echo "Application: $APP_INFO"
    else
      echo "⚠️  Application SID found but application doesn't exist"
    fi
  else
    echo "❌ No application assigned to phone number"
  fi
else
  echo "Could not determine application"
fi
echo ""

echo "5. RTP/Audio Check:"
echo "-------------------------------------------"
RTP_LOGS=$(sudo docker compose logs --since 5m rtpengine 2>/dev/null | grep -iE "(error|fail|timeout)" | tail -10 || echo "")

if [ -n "$RTP_LOGS" ]; then
  echo "RTP errors found:"
  echo "$RTP_LOGS" | sed 's/^rtpengine-1  | //'
else
  echo "✅ No RTP errors found"
fi
echo ""

echo "=========================================="
echo "Recommended Fixes"
echo "=========================================="
echo ""

if echo "$PHONE_NUMBERS" | grep -q "Empty set\|^$"; then
  echo "1. ❌ CRITICAL: Add phone number '8064061518' in Jambonz webapp"
  echo "   - Go to: Phone Numbers → Add Phone Number"
  echo "   - Number: 8064061518"
  echo "   - Carrier: Exotel"
  echo "   - Application: Select your application"
  echo ""
elif ! echo "$PHONE_NUMBERS" | grep -q "^8064061518"; then
  echo "1. ⚠️  Add phone number in format Exotel sends: '8064061518'"
  echo "   (Currently database has different format)"
  echo ""
fi

if echo "$RECENT_CALLS" | grep -q "404 Not Found"; then
  echo "2. ❌ 404 Not Found - Phone number routing failed"
  echo "   - Verify phone number is in database"
  echo "   - Check application is assigned"
  echo ""
fi

if echo "$RECENT_CALLS" | grep -q "200 OK.*BYE"; then
  echo "3. ⚠️  Call connects but disconnects - Check:"
  echo "   - Application webhook is responding correctly"
  echo "   - RTP ports are open (UDP 40000-40100)"
  echo "   - Application logic is not hanging up"
  echo ""
fi

echo "4. Check full call flow:"
echo "   sudo docker compose logs --since 5m | grep -E '8064061518|INVITE|200|BYE'"
echo ""

