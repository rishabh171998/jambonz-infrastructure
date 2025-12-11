#!/bin/bash
# Debug why heplify-server has no logs

cd "$(dirname "$0")"

echo "=========================================="
echo "Debug heplify-server No Logs"
echo "=========================================="
echo ""

echo "1. Checking heplify-server container details..."
echo "-------------------------------------------"
sudo docker compose ps heplify-server
echo ""

echo "2. Checking if heplify-server process is running..."
echo "-------------------------------------------"
HEPLIFY_PID=$(sudo docker compose exec heplify-server ps aux 2>/dev/null | grep heplify-server | grep -v grep | awk '{print $2}' || echo "")
if [ -n "$HEPLIFY_PID" ]; then
  echo "✅ heplify-server process is running (PID: $HEPLIFY_PID)"
else
  echo "❌ heplify-server process not found!"
  echo "   Container may be running but process crashed"
fi
echo ""

echo "3. Checking heplify-server logs with different methods..."
echo "-------------------------------------------"
echo "Method 1: docker compose logs"
sudo docker compose logs heplify-server --tail 20 2>&1
echo ""

echo "Method 2: docker logs directly"
sudo docker logs docker-heplify-server-1 --tail 20 2>&1
echo ""

echo "4. Checking heplify-server config file..."
echo "-------------------------------------------"
if [ -f "./heplify-server.toml" ]; then
  echo "✅ Config file exists"
  echo "Logging settings:"
  grep -E "LogLvl|LogStd|LogSys" ./heplify-server.toml || echo "  (not found)"
else
  echo "❌ Config file not found!"
fi
echo ""

echo "5. Checking if heplify-server is listening on HEP port..."
echo "-------------------------------------------"
# Check if port 9060 is listening
HEP_LISTEN=$(sudo docker compose exec heplify-server netstat -ulnp 2>/dev/null | grep ":9060 " || echo "")
if [ -n "$HEP_LISTEN" ]; then
  echo "✅ heplify-server is listening on port 9060"
  echo "$HEP_LISTEN"
else
  echo "⚠️  Could not verify port 9060 (netstat may not be available)"
  echo "   Checking if port is exposed..."
  sudo docker compose ps heplify-server | grep "9060" && echo "   ✅ Port 9060 is exposed" || echo "   ⚠️  Port 9060 not found"
fi
echo ""

echo "6. Testing if drachtio-sbc can send to heplify-server..."
echo "-------------------------------------------"
# Check if drachtio-sbc has --homer flag
DRACHTIO_CMD=$(sudo docker compose exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | grep -v grep || echo "")
if echo "$DRACHTIO_CMD" | grep -q "homer"; then
  echo "✅ drachtio-sbc has --homer flag"
  HOMER_TARGET=$(echo "$DRACHTIO_CMD" | grep -o "homer [^ ]*" | head -1)
  echo "   Target: $HOMER_TARGET"
else
  echo "❌ drachtio-sbc does NOT have --homer flag"
  echo "   Restart drachtio-sbc: sudo docker compose restart drachtio-sbc"
fi
echo ""

echo "7. Checking network connectivity..."
echo "-------------------------------------------"
# Test if drachtio-sbc can reach heplify-server
if sudo docker compose exec drachtio-sbc ping -c 2 172.10.0.41 > /dev/null 2>&1; then
  echo "✅ drachtio-sbc can reach heplify-server (172.10.0.41)"
else
  echo "❌ drachtio-sbc cannot reach heplify-server"
fi
echo ""

echo "8. Checking heplify-server container logs (all output)..."
echo "-------------------------------------------"
# Sometimes logs are in stderr or stdout separately
sudo docker logs docker-heplify-server-1 2>&1 | tail -30
echo ""

echo "=========================================="
echo "Troubleshooting"
echo "=========================================="
echo ""
echo "If heplify-server has no logs:"
echo ""
echo "1. Check if process is actually running:"
echo "   sudo docker compose exec heplify-server ps aux | grep heplify"
echo ""
echo "2. Check config file logging settings:"
echo "   grep -E 'LogLvl|LogStd|LogSys' ./heplify-server.toml"
echo "   Should have: LogStd = true (for stdout logging)"
echo ""
echo "3. Restart heplify-server:"
echo "   sudo docker compose restart heplify-server"
echo "   sudo docker compose logs -f heplify-server"
echo ""
echo "4. Make a test call and check if HEP packets arrive:"
echo "   - Make a call"
echo "   - Check logs: sudo docker compose logs heplify-server --tail 50"
echo "   - Check Homer database for calls"
echo ""
echo "5. If still no logs, check container directly:"
echo "   sudo docker exec docker-heplify-server-1 /bin/sh"
echo "   Then run: ./heplify-server -config /etc/heplify-server.toml"
echo ""

