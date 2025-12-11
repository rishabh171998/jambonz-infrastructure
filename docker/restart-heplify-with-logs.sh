#!/bin/bash
# Restart heplify-server with logging enabled

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Restart heplify-server with Logging"
echo "=========================================="
echo ""

echo "1. Checking logging configuration..."
echo "-------------------------------------------"
if grep -q "LogStd.*true" ./heplify-server.toml; then
  echo "✅ LogStd is enabled (true)"
else
  echo "❌ LogStd is disabled (false)"
  echo "   Enabling logging..."
  sed -i 's/LogStd.*false/LogStd                = true/' ./heplify-server.toml
  echo "   ✅ Updated config"
fi
echo ""

echo "2. Restarting heplify-server..."
echo "-------------------------------------------"
sudo docker compose restart heplify-server
sleep 5
echo "✅ heplify-server restarted"
echo ""

echo "3. Checking heplify-server logs..."
echo "-------------------------------------------"
sleep 2
LOGS=$(sudo docker compose logs heplify-server --tail 30 2>&1)
if [ -n "$LOGS" ]; then
  echo "✅ Logs are now appearing:"
  echo "$LOGS"
else
  echo "⚠️  Still no logs"
  echo "   Check container directly: sudo docker logs docker-heplify-server-1"
fi
echo ""

echo "4. Checking if heplify-server is receiving HEP packets..."
echo "-------------------------------------------"
echo "Make a test call, then check logs:"
echo "  sudo docker compose logs -f heplify-server"
echo ""

echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""
echo "heplify-server should now output logs."
echo "Monitor in real-time:"
echo "  sudo docker compose logs -f heplify-server"
echo ""

