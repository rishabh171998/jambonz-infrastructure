#!/bin/bash
# Test if HEP capture is working

cd "$(dirname "$0")"

echo "=========================================="
echo "Test HEP Capture"
echo "=========================================="
echo ""

echo "1. heplify-server status..."
echo "-------------------------------------------"
echo "✅ heplify-server is running and connected to database"
echo ""

echo "2. Checking if drachtio-sbc is sending HEP packets..."
echo "-------------------------------------------"
DRACHTIO_CMD=$(sudo docker compose exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | grep -v grep || echo "")
if echo "$DRACHTIO_CMD" | grep -q "homer"; then
  echo "✅ drachtio-sbc has --homer flag configured"
  HOMER_TARGET=$(echo "$DRACHTIO_CMD" | grep -o "homer [^ ]*" | head -1)
  echo "   Sending HEP to: $HOMER_TARGET"
else
  echo "❌ drachtio-sbc does NOT have --homer flag"
  echo "   Restart drachtio-sbc: sudo docker compose restart drachtio-sbc"
fi
echo ""

echo "3. Monitoring heplify-server for HEP packets..."
echo "-------------------------------------------"
echo "Make a test call now, then check logs:"
echo ""
echo "In another terminal, run:"
echo "  sudo docker compose logs -f heplify-server"
echo ""
echo "Or check recent logs:"
echo "  sudo docker compose logs heplify-server --tail 50"
echo ""

echo "4. Checking Homer database for captured calls..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  CURRENT_COUNT=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM homer_data WHERE method = 'INVITE' LIMIT 1;" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")
  echo "Current calls in Homer database: $CURRENT_COUNT"
  echo ""
  echo "After making a test call, check again:"
  echo "  sudo docker compose exec postgres psql -Uhomer -dhomer -c \"SELECT COUNT(*) FROM homer_data WHERE method = 'INVITE';\""
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "5. Testing PCAP endpoint..."
echo "-------------------------------------------"
echo "After making a test call:"
echo "  1. Go to Recent Calls in webapp"
echo "  2. Find the call"
echo "  3. Click PCAP download button"
echo "  4. Check API server logs for any errors"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Make a test call"
echo ""
echo "2. Monitor heplify-server logs in real-time:"
echo "   sudo docker compose logs -f heplify-server"
echo "   Look for HEP packet activity"
echo ""
echo "3. Check if call appears in Homer UI:"
echo "   http://localhost:9080 (or http://15.207.113.122:9080)"
echo "   Login: admin / admin123"
echo "   Search for the call"
echo ""
echo "4. If call appears in Homer, try PCAP download:"
echo "   - Go to Recent Calls page"
echo "   - Click PCAP button"
echo "   - Should download PCAP file"
echo ""
echo "5. If PCAP still fails, check:"
echo "   - API server logs: sudo docker compose logs api-server | grep -i homer"
echo "   - Fix Homer authentication if needed"
echo ""

