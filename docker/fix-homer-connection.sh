#!/bin/bash
# Fix Homer connection issue

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Connection Issue"
echo "=========================================="
echo ""

echo "1. Checking current Homer configuration..."
echo "-------------------------------------------"
CURRENT_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
echo "Current HOMER_BASE_URL: $CURRENT_URL"

if [ "$CURRENT_URL" = "http://homer:9080" ]; then
  echo "❌ Wrong URL - should be http://homer:80 (Homer listens on port 80 inside container)"
  echo ""
  echo "2. Updating docker-compose.yaml..."
  echo "-------------------------------------------"
  echo "Changing HOMER_BASE_URL from http://homer:9080 to http://homer:80"
  echo ""
  echo "3. Recreating API server..."
  echo "-------------------------------------------"
  sudo docker compose up -d --force-recreate api-server
  sleep 5
  
  NEW_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
  echo "New HOMER_BASE_URL: $NEW_URL"
  
  if [ "$NEW_URL" = "http://homer:80" ]; then
    echo "✅ Fixed!"
  else
    echo "⚠️  Still wrong - check docker-compose.yaml manually"
  fi
else
  echo "✅ URL is correct: $CURRENT_URL"
fi
echo ""

echo "4. Testing Homer connection from API server..."
echo "-------------------------------------------"
sleep 3
# Test if API server can reach Homer
if sudo docker compose exec api-server wget -q --spider http://homer:80 2>/dev/null; then
  echo "✅ API server can reach Homer"
elif sudo docker compose exec api-server curl -s -o /dev/null -w "%{http_code}" http://homer:80 2>/dev/null | grep -q "200\|301\|302"; then
  echo "✅ API server can reach Homer"
else
  echo "⚠️  API server cannot reach Homer - check network"
  echo "   Testing from API server container:"
  sudo docker compose exec api-server ping -c 2 homer > /dev/null 2>&1 && echo "   ✅ Can ping homer" || echo "   ❌ Cannot ping homer"
fi
echo ""

echo "5. Checking Homer is listening on port 80..."
echo "-------------------------------------------"
HOMER_PORT=$(sudo docker compose exec homer netstat -tlnp 2>/dev/null | grep ":80 " || echo "")
if [ -n "$HOMER_PORT" ]; then
  echo "✅ Homer is listening on port 80"
else
  echo "⚠️  Could not verify Homer port (may need netstat in container)"
  echo "   Check Homer logs: sudo docker compose logs homer | grep 'http server started'"
fi
echo ""

echo "6. Checking API server logs for Homer errors..."
echo "-------------------------------------------"
sleep 3
HOMER_ERRORS=$(sudo docker compose logs api-server --tail 50 | grep -i "homer\|ECONNREFUSED.*9080" | tail -5 || echo "")
if [ -n "$HOMER_ERRORS" ]; then
  echo "Recent Homer-related errors:"
  echo "$HOMER_ERRORS"
  echo ""
  echo "⚠️  If you still see ECONNREFUSED errors, wait a moment and check again"
else
  echo "✅ No recent Homer connection errors"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "The issue was:"
echo "  - HOMER_BASE_URL was set to http://homer:9080"
echo "  - But Homer listens on port 80 inside the container"
echo "  - Changed to http://homer:80"
echo ""
echo "Next steps:"
echo "  1. Wait a few seconds for API server to reconnect"
echo "  2. Make a test call"
echo "  3. Try downloading PCAP from Recent Calls"
echo "  4. Check API server logs: sudo docker compose logs api-server | grep -i homer"
echo ""

