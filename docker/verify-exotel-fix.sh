#!/bin/bash
# Verify Exotel fix is working

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

PHONE_NUMBER="8064061518"

echo "=========================================="
echo "Verify Exotel Fix"
echo "=========================================="
echo ""

echo "1. Gateway IPs Configuration:"
echo "-------------------------------------------"
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -n "$CARRIER_SID" ]; then
  GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT ipv4, port, protocol, inbound, outbound, is_active
  FROM sip_gateways 
  WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1
  ORDER BY ipv4;
  " 2>/dev/null || echo "")
  
  if [ -n "$GATEWAYS" ] && ! echo "$GATEWAYS" | grep -q "Empty set"; then
    echo "$GATEWAYS"
    echo ""
    
    # Check for the IPs we added
    if echo "$GATEWAYS" | grep -q "204.152.198.215\|198.143.191.202"; then
      echo "✅ Exotel source IPs are in gateways"
    else
      echo "⚠️  Exotel source IPs not found in gateways"
    fi
  else
    echo "❌ No inbound gateways found"
  fi
else
  echo "❌ Exotel carrier not found"
fi
echo ""

echo "2. Phone Number Configuration:"
echo "-------------------------------------------"
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

echo "3. Recent Call Activity (Last 5 minutes):"
echo "-------------------------------------------"
RECENT_REJECTS=$(sudo docker compose logs --since 5m sbc-inbound 2>/dev/null | grep -c "rejecting call from carrier" || echo "0")
RECENT_ACCEPTED=$(sudo docker compose logs --since 5m sbc-inbound 2>/dev/null | grep -c "inbound call accepted for routing" || echo "0")
RECENT_USER_CALLS=$(sudo docker compose logs --since 5m sbc-inbound 2>/dev/null | grep -c "incoming user call" || echo "0")

echo "  Rejected (DID not provisioned): $RECENT_REJECTS"
echo "  Accepted for routing: $RECENT_ACCEPTED"
echo "  User calls: $RECENT_USER_CALLS"
echo ""

if [ "$RECENT_REJECTS" -eq 0 ] && [ "$RECENT_ACCEPTED" -gt 0 ]; then
  echo "✅ Fix is working! Calls are being accepted"
elif [ "$RECENT_REJECTS" -eq 0 ] && [ "$RECENT_ACCEPTED" -eq 0 ]; then
  echo "⚠️  No recent calls - make a test call to verify"
elif [ "$RECENT_REJECTS" -gt 0 ]; then
  echo "❌ Still seeing rejections - check gateway IPs match source IPs"
fi
echo ""

echo "4. sbc-inbound Status:"
echo "-------------------------------------------"
if sudo docker compose ps sbc-inbound 2>/dev/null | grep -q "Up"; then
  echo "✅ sbc-inbound is running"
  
  UPTIME=$(sudo docker compose ps sbc-inbound 2>/dev/null | grep "Up" | awk '{print $5}' || echo "")
  if [ -n "$UPTIME" ]; then
    echo "   Uptime: $UPTIME"
  fi
else
  echo "❌ sbc-inbound is not running"
fi
echo ""

echo "=========================================="
echo "Test Instructions"
echo "=========================================="
echo ""
echo "1. Make a test call from Exotel to $PHONE_NUMBER"
echo ""
echo "2. Monitor logs in real-time:"
echo "   sudo docker compose logs -f sbc-inbound | grep '$PHONE_NUMBER'"
echo ""
echo "3. Expected results:"
echo "   ✅ 'inbound call accepted for routing'"
echo "   ✅ Call routes to application"
echo "   ❌ NOT 'rejecting call from carrier because DID has not been provisioned'"
echo "   ❌ NOT 'incoming user call' (unless it's actually a SIP user)"
echo ""
echo "4. If still seeing rejections:"
echo "   - Check source IP matches gateway IPs"
echo "   - Verify phone number is assigned to Exotel carrier"
echo "   - Check Request URI format"
echo ""

