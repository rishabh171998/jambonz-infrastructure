#!/bin/bash
# Check recent Exotel INVITEs and analyze Request URI format

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Recent Exotel INVITEs Analysis"
echo "=========================================="
echo ""

echo "1. Last 10 INVITEs (Request URI only):"
echo "-------------------------------------------"
sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -10 | sed 's/^drachtio-sbc-1  | //' | sed 's/ SIP\/2.0.*$//' || echo "No INVITEs found in last 30 minutes"
echo ""

echo "2. Full INVITE (most recent with headers):"
echo "-------------------------------------------"
RECENT_INVITE=$(sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep -A 20 "INVITE sip:" | tail -25 | head -25 || echo "")

if [ -z "$RECENT_INVITE" ]; then
  echo "No recent INVITEs found. Make a test call from Exotel."
  echo ""
  echo "To monitor in real-time:"
  echo "  sudo docker compose logs -f drachtio-sbc | grep 'INVITE sip:'"
  exit 0
fi

echo "$RECENT_INVITE"
echo ""

echo "3. Request URI Analysis:"
echo "-------------------------------------------"
REQUEST_URIS=$(sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -10 | sed 's/^drachtio-sbc-1  | //' | sed 's/ SIP\/2.0.*$//' || echo "")

if echo "$REQUEST_URIS" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ Phone number found in Request URI!"
  echo ""
  echo "Working examples:"
  echo "$REQUEST_URIS" | grep -E "(918064061518|08064061518)" | head -3
else
  echo "❌ Still seeing internal IDs (phone number not in Request URI)"
  echo ""
  echo "Examples:"
  echo "$REQUEST_URIS" | head -3
  echo ""
  echo "This means:"
  echo "  - Destination URI in Exotel still doesn't include phone number"
  echo "  - OR changes haven't propagated yet"
  echo "  - OR Exotel doesn't support phone number in Destination URI"
fi
echo ""

echo "4. Source IP Check:"
echo "-------------------------------------------"
SOURCE_IPS=$(sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | grep -oE "recv [0-9]+ bytes from udp/\[[0-9.]+\]" | tail -5 | sed 's/.*\[\(.*\)\]/\1/' || echo "")

if [ -n "$SOURCE_IPS" ]; then
  echo "Recent INVITEs from IPs:"
  echo "$SOURCE_IPS" | sort -u
  echo ""
  echo "Expected: 147.135.10.71 (Exotel signaling IP)"
else
  echo "Could not determine source IPs"
fi
echo ""

echo "5. Response Codes:"
echo "-------------------------------------------"
RESPONSES=$(sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep -E "(404 Not Found|200 OK|100 Trying)" | tail -10 || echo "")

if [ -n "$RESPONSES" ]; then
  echo "Recent responses:"
  echo "$RESPONSES" | sed 's/^drachtio-sbc-1  | //' | head -10
  echo ""
  
  NOT_FOUND=$(echo "$RESPONSES" | grep -c "404 Not Found" || echo "0")
  OK=$(echo "$RESPONSES" | grep -c "200 OK" || echo "0")
  
  echo "Summary:"
  echo "  404 Not Found: $NOT_FOUND"
  echo "  200 OK: $OK"
  
  if [ "$NOT_FOUND" -gt 0 ] && [ "$OK" -eq 0 ]; then
    echo ""
    echo "⚠️  All calls returning 404 - phone number routing not working"
  fi
else
  echo "No responses found (calls may have timed out or not completed)"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
if echo "$REQUEST_URIS" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ Phone number is in Request URI - routing should work!"
  echo ""
  echo "If calls still fail, check:"
  echo "  1. Phone number is in Jambonz database"
  echo "  2. Phone number has application assigned"
  echo "  3. Application is configured correctly"
else
  echo "❌ Phone number still not in Request URI"
  echo ""
  echo "Options:"
  echo "  1. Contact Exotel support to configure Request URI format"
  echo "  2. Use carrier-level application routing (all calls to one app)"
  echo "  3. Check if phone number is in other SIP headers:"
  echo "     sudo ./check-exotel-sip-headers.sh"
fi
echo ""
