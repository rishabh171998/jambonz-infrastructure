#!/bin/bash
# Restart drachtio-sbc with HEP export enabled

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Restart drachtio-sbc with HEP Export"
echo "=========================================="
echo ""

echo "1. Checking heplify-server IP..."
echo "-------------------------------------------"
HEPLIFY_IP=$(grep -A 5 "heplify-server:" docker-compose.yaml | grep "ipv4_address" | awk '{print $2}' || echo "172.10.0.41")
echo "heplify-server IP: $HEPLIFY_IP"
echo ""

echo "2. Verifying drachtio-entrypoint.sh has HEP config..."
echo "-------------------------------------------"
if grep -q "--homer" ./sbc/drachtio-entrypoint.sh; then
  echo "✅ HEP export is configured in drachtio-entrypoint.sh"
  grep "--homer" ./sbc/drachtio-entrypoint.sh
else
  echo "❌ HEP export not found in drachtio-entrypoint.sh"
  echo "   Please add: --homer \"$HEPLIFY_IP:9060\" --homer-id \"10\""
  exit 1
fi
echo ""

echo "3. Restarting drachtio-sbc..."
echo "-------------------------------------------"
sudo docker compose restart drachtio-sbc
sleep 5
echo "✅ drachtio-sbc restarted"
echo ""

echo "4. Checking drachtio-sbc logs for HEP..."
echo "-------------------------------------------"
sleep 3
if sudo docker compose logs drachtio-sbc --tail 20 | grep -qi "homer\|hep"; then
  echo "✅ HEP-related messages found:"
  sudo docker compose logs drachtio-sbc --tail 20 | grep -i "homer\|hep" | tail -5
else
  echo "⚠️  No HEP messages in logs (may be normal if no calls yet)"
fi
echo ""

echo "5. Checking heplify-server is receiving packets..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "")
if echo "$HEPLIFY_STATUS" | grep -q "Up"; then
  echo "✅ heplify-server is running"
  echo ""
  echo "   To verify HEP packets are being received:"
  echo "   - Make a test call"
  echo "   - Check heplify-server logs: sudo docker compose logs heplify-server --tail 50"
  echo "   - Check Homer UI for the call: http://localhost:9080"
else
  echo "⚠️  heplify-server is not running"
  echo "   Starting heplify-server..."
  sudo docker compose up -d heplify-server
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "drachtio-sbc is now configured to send HEP packets to heplify-server"
echo ""
echo "Next steps:"
echo "  1. Make a test call"
echo "  2. Check if call appears in Homer UI: http://localhost:9080"
echo "  3. Try downloading PCAP from Recent Calls page"
echo "  4. Monitor logs:"
echo "     sudo docker compose logs -f heplify-server"
echo "     sudo docker compose logs -f drachtio-sbc"
echo ""

