#!/bin/bash
# Check if Homer is configured for PCAP downloads

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Homer Configuration Check"
echo "=========================================="
echo ""

# Check API server environment variables
echo "1. Checking API Server Environment Variables..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

if [ -n "$HOMER_BASE_URL" ]; then
  echo "✅ HOMER_BASE_URL: $HOMER_BASE_URL"
else
  echo "❌ HOMER_BASE_URL: Not set"
fi

if [ -n "$HOMER_USERNAME" ]; then
  echo "✅ HOMER_USERNAME: $HOMER_USERNAME"
else
  echo "❌ HOMER_USERNAME: Not set"
fi

if [ -n "$HOMER_PASSWORD" ]; then
  echo "✅ HOMER_PASSWORD: *** (set)"
else
  echo "❌ HOMER_PASSWORD: Not set"
fi
echo ""

# Check if Homer is accessible
if [ -n "$HOMER_BASE_URL" ]; then
  echo "2. Testing Homer Connectivity..."
  echo "-------------------------------------------"
  HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" "$HOMER_BASE_URL" 2>/dev/null || echo "000")
  if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
    echo "✅ Homer is accessible"
  else
    echo "⚠️  Cannot reach Homer at $HOMER_BASE_URL (HTTP $HOMER_TEST)"
  fi
  echo ""
fi

# Check API server logs for Homer errors
echo "3. Checking API Server Logs for Homer Errors..."
echo "-------------------------------------------"
HOMER_ERRORS=$(sudo docker compose logs api-server --tail 100 2>/dev/null | grep -i "homer\|pcap" | tail -10 || echo "")
if [ -n "$HOMER_ERRORS" ]; then
  echo "Recent Homer/PCAP related logs:"
  echo "$HOMER_ERRORS"
else
  echo "No recent Homer/PCAP errors found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if [ -z "$HOMER_BASE_URL" ] || [ -z "$HOMER_USERNAME" ] || [ -z "$HOMER_PASSWORD" ]; then
  echo "❌ Homer is NOT configured"
  echo ""
  echo "PCAP downloads require Homer to be configured. To enable:"
  echo "  1. Set HOMER_BASE_URL in docker-compose.yaml for api-server"
  echo "  2. Set HOMER_USERNAME in docker-compose.yaml for api-server"
  echo "  3. Set HOMER_PASSWORD in docker-compose.yaml for api-server"
  echo "  4. Restart api-server: sudo docker compose restart api-server"
else
  echo "✅ Homer is configured"
  echo ""
  echo "If PCAP downloads still fail:"
  echo "  1. Verify Homer has the call data"
  echo "  2. Check that call_id format matches what Homer expects"
  echo "  3. Check API server logs for specific errors"
fi
echo ""

