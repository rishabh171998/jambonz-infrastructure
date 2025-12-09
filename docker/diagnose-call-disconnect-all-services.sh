#!/bin/bash
# Diagnose call disconnect by checking all Jambonz services

set -e

cd "$(dirname "$0")"

PHONE_NUMBER="8064061518"
TIME_RANGE="10m"

echo "=========================================="
echo "Complete Call Disconnect Diagnosis"
echo "=========================================="
echo "Phone Number: $PHONE_NUMBER"
echo "Time Range: Last $TIME_RANGE"
echo ""

echo "1. drachtio-sbc (SIP Signaling):"
echo "-------------------------------------------"
DRACHTIO_LOGS=$(sudo docker compose logs --since $TIME_RANGE drachtio-sbc 2>/dev/null | grep -E "($PHONE_NUMBER|INVITE|100 Trying|180 Ringing|200 OK|404|BYE|CANCEL|ACK)" | tail -30 || echo "")

if [ -n "$DRACHTIO_LOGS" ]; then
  echo "$DRACHTIO_LOGS" | sed 's/^drachtio-sbc-1  | //' | head -25
  
  # Count responses
  TRYING=$(echo "$DRACHTIO_LOGS" | grep -c "100 Trying" || echo "0")
  RINGING=$(echo "$DRACHTIO_LOGS" | grep -c "180 Ringing" || echo "0")
  OK=$(echo "$DRACHTIO_LOGS" | grep -c "200 OK" || echo "0")
  NOT_FOUND=$(echo "$DRACHTIO_LOGS" | grep -c "404 Not Found" || echo "0")
  BYE=$(echo "$DRACHTIO_LOGS" | grep -c "BYE" || echo "0")
  
  echo ""
  echo "Summary: 100 Trying: $TRYING | 180 Ringing: $RINGING | 200 OK: $OK | 404: $NOT_FOUND | BYE: $BYE"
else
  echo "No relevant logs found"
fi
echo ""

echo "2. sbc-inbound (Call Routing):"
echo "-------------------------------------------"
SBC_INBOUND_LOGS=$(sudo docker compose logs --since $TIME_RANGE sbc-inbound 2>/dev/null | grep -iE "($PHONE_NUMBER|routing|application|error|fail|identify)" | tail -30 || echo "")

if [ -n "$SBC_INBOUND_LOGS" ]; then
  echo "$SBC_INBOUND_LOGS" | sed 's/^sbc-inbound-1  | //' | head -25
  
  # Check for specific errors
  if echo "$SBC_INBOUND_LOGS" | grep -qi "error\|fail"; then
    echo ""
    echo "⚠️  Errors found in sbc-inbound logs"
  fi
  
  if echo "$SBC_INBOUND_LOGS" | grep -q "identifyAccount: incoming user call"; then
    echo ""
    echo "⚠️  Calls being treated as 'user calls' instead of phone number calls"
  fi
else
  echo "❌ No sbc-inbound logs found - calls may not be reaching routing service"
fi
echo ""

echo "3. call-router (Request Routing):"
echo "-------------------------------------------"
CALL_ROUTER_LOGS=$(sudo docker compose logs --since $TIME_RANGE call-router 2>/dev/null | grep -iE "($PHONE_NUMBER|invite|route|error)" | tail -20 || echo "")

if [ -n "$CALL_ROUTER_LOGS" ]; then
  echo "$CALL_ROUTER_LOGS" | sed 's/^call-router-1  | //' | head -20
else
  echo "No relevant logs found"
fi
echo ""

echo "4. feature-server (Call Application Logic):"
echo "-------------------------------------------"
FEATURE_LOGS=$(sudo docker compose logs --since $TIME_RANGE feature-server 2>/dev/null | grep -iE "($PHONE_NUMBER|call|error|fail|hangup|disconnect)" | tail -30 || echo "")

if [ -n "$FEATURE_LOGS" ]; then
  echo "$FEATURE_LOGS" | sed 's/^feature-server-1  | //' | head -25
  
  if echo "$FEATURE_LOGS" | grep -qi "error\|fail"; then
    echo ""
    echo "⚠️  Errors found in feature-server logs"
  fi
else
  echo "No relevant logs found (call may not have reached feature-server)"
fi
echo ""

echo "5. api-server (Webhooks & API):"
echo "-------------------------------------------"
API_LOGS=$(sudo docker compose logs --since $TIME_RANGE api-server 2>/dev/null | grep -iE "($PHONE_NUMBER|webhook|call|error)" | tail -20 || echo "")

if [ -n "$API_LOGS" ]; then
  echo "$API_LOGS" | sed 's/^api-server-1  | //' | head -20
  
  if echo "$API_LOGS" | grep -qi "error\|fail\|timeout"; then
    echo ""
    echo "⚠️  API/webhook errors found"
  fi
else
  echo "No relevant logs found"
fi
echo ""

echo "6. rtpengine (RTP/Audio):"
echo "-------------------------------------------"
RTP_LOGS=$(sudo docker compose logs --since $TIME_RANGE rtpengine 2>/dev/null | grep -iE "(error|fail|timeout|reject)" | tail -20 || echo "")

if [ -n "$RTP_LOGS" ]; then
  echo "$RTP_LOGS" | sed 's/^rtpengine-1  | //' | head -20
  echo ""
  echo "⚠️  RTP errors found - may cause audio issues"
else
  echo "✅ No RTP errors found"
fi
echo ""

echo "7. freeswitch (Media Server):"
echo "-------------------------------------------"
FS_LOGS=$(sudo docker compose logs --since $TIME_RANGE freeswitch 2>/dev/null | grep -iE "($PHONE_NUMBER|error|fail|hangup)" | tail -20 || echo "")

if [ -n "$FS_LOGS" ]; then
  echo "$FS_LOGS" | sed 's/^freeswitch-1  | //' | head -20
else
  echo "No relevant logs found"
fi
echo ""

echo "=========================================="
echo "Call Flow Analysis"
echo "=========================================="
echo ""

# Check if call reached each stage
REACHED_DRACHTIO=$(echo "$DRACHTIO_LOGS" | grep -c "INVITE.*$PHONE_NUMBER" || echo "0")
REACHED_SBC_INBOUND=$(echo "$SBC_INBOUND_LOGS" | grep -c "$PHONE_NUMBER\|routing" || echo "0")
REACHED_FEATURE=$(echo "$FEATURE_LOGS" | grep -c "$PHONE_NUMBER\|call" || echo "0")

echo "Call progression:"
echo "  ✅ drachtio-sbc (SIP received): $REACHED_DRACHTIO"
echo "  $(if [ "$REACHED_SBC_INBOUND" -gt 0 ]; then echo "✅"; else echo "❌"; fi) sbc-inbound (routing): $REACHED_SBC_INBOUND"
echo "  $(if [ "$REACHED_FEATURE" -gt 0 ]; then echo "✅"; else echo "❌"; fi) feature-server (application): $REACHED_FEATURE"
echo ""

if [ "$REACHED_DRACHTIO" -gt 0 ] && [ "$REACHED_SBC_INBOUND" -eq 0 ]; then
  echo "❌ PROBLEM: Call received but not reaching sbc-inbound"
  echo ""
  echo "Possible causes:"
  echo "  1. Gateway IP not whitelisted (inbound=0)"
  echo "  2. Request URI format causing routing failure"
  echo "  3. SIP realm matching instead of phone number matching"
  echo ""
  echo "Fix: Check gateway configuration and Request URI format"
elif [ "$REACHED_SBC_INBOUND" -gt 0 ] && [ "$REACHED_FEATURE" -eq 0 ]; then
  echo "❌ PROBLEM: Call routed but not reaching feature-server"
  echo ""
  echo "Possible causes:"
  echo "  1. Application not configured"
  echo "  2. Application webhook failing"
  echo "  3. Feature-server connection issue"
  echo ""
  echo "Fix: Check application configuration and feature-server logs"
elif [ "$REACHED_FEATURE" -gt 0 ]; then
  echo "✅ Call reached feature-server"
  echo ""
  if [ "$BYE" -gt 0 ] && [ "$OK" -gt 0 ]; then
    echo "Call connected (200 OK) but then disconnected (BYE)"
    echo "Check: Application logic, webhook responses, RTP issues"
  fi
fi
echo ""

echo "=========================================="
echo "Recommended Actions"
echo "=========================================="
echo ""

if [ "$REACHED_SBC_INBOUND" -eq 0 ]; then
  echo "1. Add Exotel source IPs to gateways:"
  echo "   sudo ./fix-exotel-phone-number-routing.sh"
  echo ""
  echo "2. Update Exotel Destination URI:"
  echo "   Change to: sip:8064061518@15.207.113.122"
  echo "   (Use IP instead of FQDN to avoid SIP realm matching)"
  echo ""
fi

if [ "$REACHED_FEATURE" -eq 0 ] && [ "$REACHED_SBC_INBOUND" -gt 0 ]; then
  echo "1. Check application configuration:"
  echo "   sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e \""
  echo "   SELECT number, application_sid FROM phone_numbers WHERE number = '$PHONE_NUMBER';\""
  echo ""
  echo "2. Check application webhook:"
  echo "   Review api-server logs for webhook call attempts"
  echo ""
fi

if [ "$NOT_FOUND" -gt 0 ]; then
  echo "1. 404 Not Found - Phone number routing failed"
  echo "   Verify phone number is in database and has application assigned"
  echo ""
fi

echo "2. Monitor real-time:"
echo "   sudo docker compose logs -f sbc-inbound | grep '$PHONE_NUMBER'"
echo ""

