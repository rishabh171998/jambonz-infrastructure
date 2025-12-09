#!/bin/bash
# Check for actual Exotel calls (INVITEs) vs health checks (OPTIONS)

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel Call Activity Check"
echo "=========================================="
echo ""

echo "1. Recent INVITEs (Actual Calls):"
echo "-------------------------------------------"
INVITES=$(sudo docker compose logs --since 1h drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -10 || echo "")

if [ -z "$INVITES" ]; then
  echo "❌ No INVITEs found in last hour"
  echo ""
  echo "This means:"
  echo "  - No calls have been made from Exotel recently"
  echo "  - OR calls are not reaching Jambonz"
  echo ""
  echo "To test: Make a call from Exotel to +918064061518"
else
  echo "Found INVITEs:"
  echo "$INVITES" | sed 's/^drachtio-sbc-1  | //' | head -10
  echo ""
  
  # Check if phone number is in Request URI
  if echo "$INVITES" | grep -qE "(918064061518|08064061518)"; then
    echo "✅ Phone number found in Request URI!"
  else
    echo "❌ Still seeing internal IDs (phone number not in Request URI)"
  fi
fi
echo ""

echo "2. Recent OPTIONS (Health Checks - Normal):"
echo "-------------------------------------------"
OPTIONS_COUNT=$(sudo docker compose logs --since 1h drachtio-sbc 2>/dev/null | grep -c "OPTIONS sip:" || echo "0")
echo "OPTIONS requests: $OPTIONS_COUNT (these are normal health checks from FreeSWITCH)"
echo ""

echo "3. Source IPs of Recent INVITEs:"
echo "-------------------------------------------"
if [ -n "$INVITES" ]; then
  SOURCE_IPS=$(sudo docker compose logs --since 1h drachtio-sbc 2>/dev/null | grep "INVITE sip:" | grep -oE "recv [0-9]+ bytes from udp/\[[0-9.]+\]" | sed 's/.*\[\(.*\)\]/\1/' | sort -u || echo "")
  if [ -n "$SOURCE_IPS" ]; then
    echo "INVITEs from:"
    echo "$SOURCE_IPS"
    echo ""
    if echo "$SOURCE_IPS" | grep -q "147.135.10.71"; then
      echo "✅ INVITEs from Exotel IP (147.135.10.71)"
    else
      echo "⚠️  INVITEs from different IPs (may not be from Exotel)"
    fi
  fi
else
  echo "No INVITEs to analyze"
fi
echo ""

echo "4. Response Codes for INVITEs:"
echo "-------------------------------------------"
if [ -n "$INVITES" ]; then
  RESPONSES=$(sudo docker compose logs --since 1h drachtio-sbc 2>/dev/null | grep -E "(404 Not Found|200 OK|100 Trying|180 Ringing)" | tail -20 || echo "")
  if [ -n "$RESPONSES" ]; then
    echo "Recent responses:"
    echo "$RESPONSES" | sed 's/^drachtio-sbc-1  | //' | head -10
    echo ""
    
    NOT_FOUND=$(echo "$RESPONSES" | grep -c "404 Not Found" || echo "0")
    OK=$(echo "$RESPONSES" | grep -c "200 OK" || echo "0")
    TRYING=$(echo "$RESPONSES" | grep -c "100 Trying" || echo "0")
    
    echo "Summary:"
    echo "  100 Trying: $TRYING"
    echo "  404 Not Found: $NOT_FOUND"
    echo "  200 OK: $OK"
  else
    echo "No responses found"
  fi
else
  echo "No INVITEs to check responses for"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ -z "$INVITES" ]; then
  echo "❌ No Exotel calls detected in last hour"
  echo ""
  echo "Next steps:"
  echo "  1. Make a test call from Exotel to +918064061518"
  echo "  2. Wait 30 seconds"
  echo "  3. Run this script again: sudo ./check-exotel-calls.sh"
  echo "  4. Or monitor in real-time:"
  echo "     sudo docker compose logs -f drachtio-sbc | grep 'INVITE sip:'"
else
  echo "✅ Exotel calls detected"
  echo ""
  if echo "$INVITES" | grep -qE "(918064061518|08064061518)"; then
    echo "✅ Phone number is in Request URI - routing should work!"
  else
    echo "❌ Phone number NOT in Request URI - still seeing internal IDs"
    echo ""
    echo "This means Exotel Destination URI still doesn't include phone number."
    echo "Options:"
    echo "  1. Contact Exotel support"
    echo "  2. Use carrier-level application routing"
    echo "  3. Check other SIP headers: sudo ./check-exotel-sip-headers.sh"
  fi
fi
echo ""

echo "Note: OPTIONS messages are normal - they're health checks from FreeSWITCH"
echo ""

