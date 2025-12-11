#!/bin/bash
# Verify HEP is working - check if SIP traffic is being captured

cd "$(dirname "$0")"

echo "=========================================="
echo "Verify HEP is Working"
echo "=========================================="
echo ""

echo "1. Checking drachtio-sbc is running with HEP..."
echo "-------------------------------------------"
DRACHTIO_STATUS=$(sudo docker compose ps drachtio-sbc --format "{{.Status}}" 2>/dev/null || echo "")
echo "drachtio-sbc status: $DRACHTIO_STATUS"

# Check if drachtio process has --homer flag
DRACHTIO_CMD=$(sudo docker compose exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | grep -v grep || echo "")
if echo "$DRACHTIO_CMD" | grep -q "homer"; then
  echo "✅ drachtio-sbc has --homer flag"
  echo "$DRACHTIO_CMD" | grep -o "homer[^ ]*" | head -2
else
  echo "❌ drachtio-sbc does NOT have --homer flag"
  echo "   Command: $DRACHTIO_CMD"
  echo "   Restart drachtio-sbc: sudo docker compose restart drachtio-sbc"
fi
echo ""

echo "2. Checking heplify-server is running..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "")
echo "heplify-server status: $HEPLIFY_STATUS"

if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "⚠️  heplify-server is restarting - check logs"
  sudo docker compose logs heplify-server --tail 20 | tail -10
elif echo "$HEPLIFY_STATUS" | grep -q "Up"; then
  echo "✅ heplify-server is running"
else
  echo "❌ heplify-server is not running"
fi
echo ""

echo "3. Checking if heplify-server is receiving HEP packets..."
echo "-------------------------------------------"
# Check heplify-server logs for HEP activity
HEP_ACTIVITY=$(sudo docker compose logs heplify-server --tail 100 2>/dev/null | grep -iE "hep|packet|received|stored" | tail -10 || echo "")
if [ -n "$HEP_ACTIVITY" ]; then
  echo "✅ HEP activity found in heplify-server logs:"
  echo "$HEP_ACTIVITY"
else
  echo "⚠️  No HEP activity in heplify-server logs"
  echo "   This could mean:"
  echo "   - No calls have been made yet"
  echo "   - drachtio-sbc is not sending HEP packets"
  echo "   - Network connectivity issue"
fi
echo ""

echo "4. Checking Homer database for captured calls..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  HOMER_CALLS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM homer_data WHERE method = 'INVITE' LIMIT 1;" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")
  echo "Calls in Homer database: $HOMER_CALLS"
  
  if [ "$HOMER_CALLS" != "0" ] && [ -n "$HOMER_CALLS" ] && [ "$HOMER_CALLS" != "" ]; then
    echo "✅ Calls are being captured!"
    
    # Get a recent call
    RECENT_CALL=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT callid, method, created_date FROM homer_data WHERE method = 'INVITE' ORDER BY created_date DESC LIMIT 1;" 2>/dev/null | grep -v "callid\|row\|---" | head -1 || echo "")
    if [ -n "$RECENT_CALL" ]; then
      echo "   Recent call: $RECENT_CALL"
    fi
  else
    echo "⚠️  No calls captured yet"
    echo "   Make a test call and check again"
  fi
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "5. Testing network connectivity..."
echo "-------------------------------------------"
# Test if drachtio-sbc can reach heplify-server
if sudo docker compose exec drachtio-sbc ping -c 2 172.10.0.41 > /dev/null 2>&1; then
  echo "✅ drachtio-sbc can reach heplify-server (172.10.0.41)"
else
  echo "❌ drachtio-sbc cannot reach heplify-server"
fi

# Test UDP port 9060
if sudo docker compose exec drachtio-sbc nc -zu 172.10.0.41 9060 2>/dev/null; then
  echo "✅ Port 9060 (HEP) is accessible"
else
  echo "⚠️  Cannot verify port 9060 (nc may not be available)"
fi
echo ""

echo "6. Checking drachtio-sbc logs for HEP errors..."
echo "-------------------------------------------"
HEP_ERRORS=$(sudo docker compose logs drachtio-sbc --tail 100 | grep -iE "homer|hep|error.*9060" | tail -10 || echo "")
if [ -n "$HEP_ERRORS" ]; then
  echo "HEP-related messages/errors:"
  echo "$HEP_ERRORS"
else
  echo "✅ No HEP errors in drachtio-sbc logs"
  echo "   (Note: drachtio may not log HEP sends, only errors)"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "To verify HEP is working:"
echo ""
echo "1. Make a test call"
echo "2. Check Homer UI: http://localhost:9080"
echo "   - Login: admin / admin123"
echo "   - Search for the call"
echo "   - If call appears, HEP is working!"
echo ""
echo "3. Check heplify-server logs:"
echo "   sudo docker compose logs heplify-server --tail 50"
echo ""
echo "4. Check Homer database:"
echo "   sudo docker compose exec postgres psql -Uhomer -dhomer -c \"SELECT COUNT(*) FROM homer_data;\""
echo ""
echo "If calls are not appearing in Homer:"
echo "  - Verify drachtio-sbc has --homer flag (step 1 above)"
echo "  - Restart drachtio-sbc: sudo docker compose restart drachtio-sbc"
echo "  - Check network connectivity (step 5 above)"
echo ""

