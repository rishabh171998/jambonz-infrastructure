#!/bin/bash
# Comprehensive diagnosis for calls not connecting

set -e

cd "$(dirname "$0")"

PHONE_NUMBER="8064061518"
TIME_RANGE="5m"

echo "=========================================="
echo "Complete Call Connection Diagnosis"
echo "=========================================="
echo "Phone Number: $PHONE_NUMBER"
echo "Time Range: Last $TIME_RANGE"
echo ""

echo "1. Recent Call Activity:"
echo "-------------------------------------------"
RECENT_LOGS=$(sudo docker compose logs --since $TIME_RANGE sbc-inbound 2>/dev/null | grep -iE "($PHONE_NUMBER|rejecting|accepted|routing|error)" | tail -20 || echo "")

if [ -z "$RECENT_LOGS" ]; then
  echo "❌ No recent activity - make a test call first"
  echo ""
  echo "Then run: sudo docker compose logs -f sbc-inbound"
else
  echo "$RECENT_LOGS" | sed 's/^sbc-inbound-1  | //'
  
  REJECTS=$(echo "$RECENT_LOGS" | grep -c "rejecting call" || echo "0")
  ACCEPTED=$(echo "$RECENT_LOGS" | grep -c "accepted for routing" || echo "0")
  
  echo ""
  echo "Summary:"
  echo "  Rejected: $REJECTS"
  echo "  Accepted: $ACCEPTED"
fi
echo ""

echo "2. Full Call Flow (drachtio-sbc):"
echo "-------------------------------------------"
DRACHTIO_FLOW=$(sudo docker compose logs --since $TIME_RANGE drachtio-sbc 2>/dev/null | grep -E "($PHONE_NUMBER|INVITE|100 Trying|180 Ringing|200 OK|404|BYE|CANCEL)" | tail -30 || echo "")

if [ -n "$DRACHTIO_FLOW" ]; then
  echo "$DRACHTIO_FLOW" | sed 's/^drachtio-sbc-1  | //' | head -25
  
  # Analyze flow
  INVITE=$(echo "$DRACHTIO_FLOW" | grep -c "INVITE.*$PHONE_NUMBER" || echo "0")
  TRYING=$(echo "$DRACHTIO_FLOW" | grep -c "100 Trying" || echo "0")
  RINGING=$(echo "$DRACHTIO_FLOW" | grep -c "180 Ringing" || echo "0")
  OK=$(echo "$DRACHTIO_FLOW" | grep -c "200 OK" || echo "0")
  NOT_FOUND=$(echo "$DRACHTIO_FLOW" | grep -c "404 Not Found" || echo "0")
  BYE=$(echo "$DRACHTIO_FLOW" | grep -c "BYE" || echo "0")
  
  echo ""
  echo "Call flow:"
  echo "  INVITE: $INVITE"
  echo "  100 Trying: $TRYING"
  echo "  180 Ringing: $RINGING"
  echo "  200 OK: $OK"
  echo "  404 Not Found: $NOT_FOUND"
  echo "  BYE: $BYE"
  
  if [ "$NOT_FOUND" -gt 0 ]; then
    echo ""
    echo "❌ 404 Not Found - Routing failed"
  elif [ "$OK" -gt 0 ] && [ "$BYE" -gt 0 ]; then
    echo ""
    echo "⚠️  Call connected but then disconnected"
  elif [ "$OK" -eq 0 ] && [ "$INVITE" -gt 0 ]; then
    echo ""
    echo "⚠️  INVITE received but no 200 OK - call not completing"
  fi
else
  echo "No recent call activity in drachtio-sbc"
fi
echo ""

echo "3. sbc-inbound Detailed Logs:"
echo "-------------------------------------------"
SBC_DETAILED=$(sudo docker compose logs --since $TIME_RANGE sbc-inbound 2>/dev/null | grep -A 5 -B 5 "$PHONE_NUMBER" | tail -40 || echo "")

if [ -n "$SBC_DETAILED" ]; then
  echo "$SBC_DETAILED" | sed 's/^sbc-inbound-1  | //' | head -35
else
  echo "No detailed logs found for $PHONE_NUMBER"
fi
echo ""

echo "4. feature-server Logs:"
echo "-------------------------------------------"
FEATURE_LOGS=$(sudo docker compose logs --since $TIME_RANGE feature-server 2>/dev/null | grep -iE "($PHONE_NUMBER|call|error|fail)" | tail -20 || echo "")

if [ -n "$FEATURE_LOGS" ]; then
  echo "$FEATURE_LOGS" | sed 's/^feature-server-1  | //' | head -20
  
  if echo "$FEATURE_LOGS" | grep -qi "error\|fail"; then
    echo ""
    echo "⚠️  Errors found in feature-server"
  fi
else
  echo "No feature-server logs found"
  echo "  (Call may not have reached feature-server)"
fi
echo ""

echo "5. Gateway IP Verification:"
echo "-------------------------------------------"
# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -n "$CARRIER_SID" ]; then
  GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT ipv4, inbound, is_active
  FROM sip_gateways 
  WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
  " 2>/dev/null || echo "")
  
  if [ -n "$GATEWAYS" ] && ! echo "$GATEWAYS" | grep -q "Empty set"; then
    echo "$GATEWAYS"
    
    # Check for the IPs we added
    if echo "$GATEWAYS" | grep -q "204.152.198.215\|198.143.191.202"; then
      echo ""
      echo "✅ Exotel gateway IPs are configured"
    fi
  else
    echo "❌ No inbound gateways found"
  fi
fi
echo ""

echo "6. Phone Number Configuration:"
echo "-------------------------------------------"
if [ -n "$CARRIER_SID" ]; then
  PHONE_CONFIG=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT number, voip_carrier_sid, application_sid
  FROM phone_numbers 
  WHERE number = '$PHONE_NUMBER';
  " 2>/dev/null || echo "")
  
  if [ -n "$PHONE_CONFIG" ] && ! echo "$PHONE_CONFIG" | grep -q "Empty set"; then
    echo "$PHONE_CONFIG"
    
    APP_SID=$(echo "$PHONE_CONFIG" | grep -v "application_sid" | awk '{print $3}' | head -1 || echo "")
    if [ -n "$APP_SID" ] && [ "$APP_SID" != "NULL" ]; then
      echo ""
      echo "✅ Application assigned: $APP_SID"
    else
      echo ""
      echo "❌ No application assigned to phone number"
    fi
  else
    echo "❌ Phone number not found in database"
  fi
fi
echo ""

echo "=========================================="
echo "Diagnosis Summary"
echo "=========================================="
echo ""

if echo "$RECENT_LOGS" | grep -q "rejecting call"; then
  echo "❌ PROBLEM: Calls still being rejected"
  echo ""
  echo "Possible causes:"
  echo "  1. Source IP doesn't match gateway IPs"
  echo "  2. Phone number not assigned to Exotel carrier"
  echo "  3. Gateway IPs not active (is_active=0)"
  echo ""
  echo "Fix: Run sudo ./add-exotel-gateway-ips.sh again"
elif [ "$NOT_FOUND" -gt 0 ]; then
  echo "❌ PROBLEM: 404 Not Found"
  echo ""
  echo "Possible causes:"
  echo "  1. Phone number not in database"
  echo "  2. Application not assigned"
  echo "  3. Request URI format issue"
  echo ""
  echo "Fix: Verify phone number and application configuration"
elif [ "$OK" -eq 0 ] && [ "$INVITE" -gt 0 ]; then
  echo "❌ PROBLEM: INVITE received but call not completing"
  echo ""
  echo "Possible causes:"
  echo "  1. Application webhook failing"
  echo "  2. Feature-server not responding"
  echo "  3. RTP/audio issues"
  echo ""
  echo "Fix: Check feature-server and api-server logs"
elif [ "$OK" -gt 0 ] && [ "$BYE" -gt 0 ]; then
  echo "⚠️  Call connects but disconnects immediately"
  echo ""
  echo "Possible causes:"
  echo "  1. Application logic hanging up"
  echo "  2. RTP/audio negotiation failure"
  echo "  3. Webhook timeout"
  echo ""
  echo "Fix: Check feature-server logs and RTP configuration"
else
  echo "⚠️  No recent call activity detected"
  echo ""
  echo "Make a test call and run this script again"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Make a test call from Exotel"
echo ""
echo "2. Monitor in real-time:"
echo "   sudo docker compose logs -f sbc-inbound drachtio-sbc | grep '$PHONE_NUMBER'"
echo ""
echo "3. Check specific service:"
echo "   sudo docker compose logs -f feature-server"
echo "   sudo docker compose logs -f api-server"
echo ""

