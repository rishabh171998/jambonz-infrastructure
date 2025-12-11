#!/bin/bash
# Rebuild webapp with the recent calls fix

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Rebuild Webapp with Recent Calls Fix"
echo "=========================================="
echo ""

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "1. Verifying fix is applied..."
echo "-------------------------------------------"
WEBAPP_FILE="jambonz-webapp-main/src/containers/internal/views/recent-calls/index.tsx"
if grep -q "if (json && json.data && Array.isArray(json.data))" "$WEBAPP_FILE" 2>/dev/null; then
  echo "✅ Fix is applied in webapp source"
else
  echo "⚠️  Fix not found in webapp source"
  echo "   Applying fix now..."
  ./fix-recent-calls-simple.sh
fi
echo ""

echo "2. Rebuilding webapp..."
echo "-------------------------------------------"
echo "   This may take a few minutes..."
$DOCKER_CMD build webapp
echo "   ✅ Webapp rebuilt"
echo ""

echo "3. Restarting webapp..."
echo "-------------------------------------------"
$DOCKER_CMD restart webapp
echo "   ✅ Webapp restarted"
echo ""

echo "4. Waiting for webapp to be ready..."
echo "-------------------------------------------"
sleep 5

# Check if webapp is responding
WEBAPP_STATUS=$($DOCKER_CMD ps --filter "name=webapp" --format "{{.Status}}" 2>/dev/null || echo "")
if [ -n "$WEBAPP_STATUS" ]; then
  echo "   ✅ Webapp status: $WEBAPP_STATUS"
else
  echo "   ⚠️  Could not check webapp status"
fi
echo ""

echo "=========================================="
echo "✅ Rebuild Complete"
echo "=========================================="
echo ""
echo "The recent calls page should now work properly."
echo ""
echo "To test:"
echo "  1. Open the webapp in your browser"
echo "  2. Navigate to 'Recent Calls'"
echo "  3. The page should load without errors"
echo ""
echo "If you still see issues:"
echo "  1. Check browser console (F12) for errors"
echo "  2. Check webapp logs: sudo docker compose logs webapp"
echo "  3. Verify API is working: curl http://localhost:3000/v1/Accounts/YOUR_ACCOUNT_SID/RecentCalls"
echo ""

