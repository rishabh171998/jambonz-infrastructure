#!/bin/bash
# Troubleshoot Exotel Destination URI issue

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel Destination URI Troubleshooting"
echo "=========================================="
echo ""

echo "1. Recent INVITE Request URIs:"
echo "-------------------------------------------"
echo "Checking last 10 INVITEs..."
sudo docker compose logs --since 5m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -10 | sed 's/^drachtio-sbc-1  | //' || echo "No recent INVITEs"

echo ""
echo "2. Analysis:"
echo "-------------------------------------------"
RECENT=$(sudo docker compose logs --since 5m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -5 | sed 's/^drachtio-sbc-1  | //' || echo "")

if echo "$RECENT" | grep -qE "(918064061518|08064061518)"; then
  echo "✅ Phone number found in Request URI - Configuration is working!"
else
  echo "❌ Still seeing internal IDs - Destination URI not applied correctly"
  echo ""
  echo "Common issues:"
  echo "  1. Destination URI not saved in Exotel dashboard"
  echo "  2. Changes haven't propagated (wait 2-3 minutes)"
  echo "  3. Format not accepted by Exotel"
  echo "  4. Multiple trunks configured (wrong one being used)"
fi
echo ""

echo "3. Expected vs Actual:"
echo "-------------------------------------------"
echo "❌ Current (from logs):"
echo "   INVITE sip:284700441224015426@15.207.113.122"
echo ""
echo "✅ Should be:"
echo "   INVITE sip:+918064061518@15.207.113.122"
echo "   (or: INVITE sip:918064061518@15.207.113.122)"
echo ""

echo "4. Verification Steps:"
echo "-------------------------------------------"
echo ""
echo "In Exotel Dashboard:"
echo "  1. Go to: Trunk Configuration → Your Trunk"
echo "  2. Check 'Destination URIs' field"
echo "  3. Should show: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "  4. If different, update and SAVE"
echo ""
echo "If Destination URI is correct but still not working:"
echo "  - Wait 2-3 minutes for propagation"
echo "  - Try making a new call (not retry of old call)"
echo "  - Check if phone number is assigned to the correct trunk"
echo "  - Contact Exotel support if issue persists"
echo ""

echo "5. Alternative Formats to Try:"
echo "-------------------------------------------"
echo ""
echo "If sip:+918064061518@... doesn't work, try:"
echo ""
echo "  Option 1 (without +):"
echo "    sip:918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "  Option 2 (local format):"
echo "    sip:08064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "  Option 3 (E.164 with different format):"
echo "    sip:+91-8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""

echo "6. Check Phone Number Assignment:"
echo "-------------------------------------------"
echo "Verify in Exotel dashboard:"
echo "  - Phone Number: +918064061518"
echo "  - Assigned to Trunk: exotel (trmum1b5bb8024884011b3b019c9)"
echo "  - Destination URI includes the phone number"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Double-check Destination URI in Exotel dashboard"
echo "2. Make sure it's saved (click SAVE button)"
echo "3. Wait 2-3 minutes"
echo "4. Make a NEW test call (don't retry old calls)"
echo "5. Check logs again:"
echo "   sudo docker compose logs -f drachtio-sbc | grep 'INVITE sip:'"
echo ""

