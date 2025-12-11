#!/bin/bash
# Check heplify-server status and logs

cd "$(dirname "$0")"

echo "=========================================="
echo "Check heplify-server Status"
echo "=========================================="
echo ""

echo "1. Checking service name..."
echo "-------------------------------------------"
echo "Service name is: heplify-server (not heplify-serve)"
echo ""

echo "2. Checking if heplify-server is running..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "not found")
echo "heplify-server status: $HEPLIFY_STATUS"

if [ "$HEPLIFY_STATUS" = "not found" ]; then
  echo "❌ Service not found!"
  echo ""
  echo "Available services:"
  sudo docker compose ps --format "{{.Service}}" | grep -i hep || echo "  (none found)"
  echo ""
  echo "Check docker-compose.yaml for the correct service name"
else
  echo "✅ Service found"
fi
echo ""

echo "3. Checking heplify-server logs..."
echo "-------------------------------------------"
if [ "$HEPLIFY_STATUS" != "not found" ]; then
  echo "Last 50 lines of heplify-server logs:"
  sudo docker compose logs heplify-server --tail 50
else
  echo "⚠️  Cannot check logs - service not found"
fi
echo ""

echo "4. All services with 'hep' in name..."
echo "-------------------------------------------"
sudo docker compose ps | grep -i hep || echo "No services found"
echo ""

echo "=========================================="
echo "Correct Commands"
echo "=========================================="
echo ""
echo "To check heplify-server logs:"
echo "  sudo docker compose logs heplify-server"
echo ""
echo "To follow logs in real-time:"
echo "  sudo docker compose logs -f heplify-server"
echo ""
echo "To check status:"
echo "  sudo docker compose ps heplify-server"
echo ""
echo "To restart:"
echo "  sudo docker compose restart heplify-server"
echo ""

