#!/bin/bash
# Restart Homer services with fixes

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Restarting Homer Services"
echo "=========================================="
echo ""

echo "1. Restarting Homer with correct port mapping..."
echo "-------------------------------------------"
sudo docker compose up -d --force-recreate homer
sleep 5
echo "✅ Homer restarted"
echo ""

echo "2. Restarting heplify-server with config..."
echo "-------------------------------------------"
sudo docker compose up -d --force-recreate heplify-server
sleep 3
echo "✅ heplify-server restarted"
echo ""

echo "3. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps homer heplify-server
echo ""

echo "4. Testing Homer web interface..."
echo "-------------------------------------------"
sleep 3
HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer web interface is accessible (HTTP $HOMER_TEST)"
  echo "   URL: http://localhost:9080"
else
  echo "⚠️  Homer web interface not accessible (HTTP $HOMER_TEST)"
  echo "   Checking logs..."
  sudo docker compose logs homer --tail 10
fi
echo ""

echo "5. Checking heplify-server status..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "")
if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "⚠️  heplify-server is still restarting"
  echo "   Checking logs..."
  sudo docker compose logs heplify-server --tail 20 | tail -10
else
  echo "✅ heplify-server status: $HEPLIFY_STATUS"
fi
echo ""

echo "=========================================="
echo "Done!"
echo "=========================================="
echo ""

