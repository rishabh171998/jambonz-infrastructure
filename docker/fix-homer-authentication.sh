#!/bin/bash
# Fix Homer authentication for API server

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Authentication"
echo "=========================================="
echo ""

echo "1. Checking API server Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

echo "HOMER_BASE_URL: $HOMER_BASE_URL"
echo "HOMER_USERNAME: $HOMER_USERNAME"
echo "HOMER_PASSWORD: *** (configured: $([ -n "$HOMER_PASSWORD" ] && echo "yes" || echo "no"))"
echo ""

echo "2. Testing Homer connection from API server..."
echo "-------------------------------------------"
# Test if API server can reach Homer
if sudo docker compose exec api-server wget -q --spider http://homer:80 2>/dev/null; then
  echo "✅ API server can reach Homer"
elif sudo docker compose exec api-server curl -s -o /dev/null -w "%{http_code}" http://homer:80 2>/dev/null | grep -q "200\|301\|302"; then
  echo "✅ API server can reach Homer"
else
  echo "⚠️  API server cannot reach Homer HTTP"
  echo "   Testing ping..."
  sudo docker compose exec api-server ping -c 2 homer > /dev/null 2>&1 && echo "   ✅ Can ping homer" || echo "   ❌ Cannot ping homer"
fi
echo ""

echo "3. Checking Homer authentication endpoint..."
echo "-------------------------------------------"
# Homer API endpoint for getting API key: /api/v3/auth
# Test if we can access it
HOMER_AUTH_TEST=$(sudo docker compose exec api-server curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"$HOMER_USERNAME\",\"password\":\"$HOMER_PASSWORD\"}" \
  "http://homer:80/api/v3/auth" 2>/dev/null || echo "")

if [ -n "$HOMER_AUTH_TEST" ]; then
  if echo "$HOMER_AUTH_TEST" | grep -q "token\|apikey\|success"; then
    echo "✅ Homer authentication endpoint is working"
    echo "   Response: $(echo "$HOMER_AUTH_TEST" | head -c 100)"
  else
    echo "⚠️  Homer authentication may have issues"
    echo "   Response: $HOMER_AUTH_TEST"
  fi
else
  echo "⚠️  Could not test authentication (curl may not be available in container)"
fi
echo ""

echo "4. Checking Homer users in database..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  HOMER_USERS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT username, active FROM users WHERE username = 'admin' LIMIT 1;" 2>/dev/null | grep -E "admin|t|f" | head -1 || echo "")
  if [ -n "$HOMER_USERS" ]; then
    echo "Homer users:"
    echo "$HOMER_USERS"
  else
    echo "⚠️  Could not query Homer users"
    echo "   Homer may need to be initialized"
  fi
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "5. Checking Homer logs for authentication errors..."
echo "-------------------------------------------"
HOMER_AUTH_ERRORS=$(sudo docker compose logs homer --tail 50 | grep -iE "auth|login|error" | tail -10 || echo "")
if [ -n "$HOMER_AUTH_ERRORS" ]; then
  echo "Recent Homer auth-related logs:"
  echo "$HOMER_AUTH_ERRORS"
else
  echo "✅ No auth errors in Homer logs"
fi
echo ""

echo "6. Testing Homer web interface login..."
echo "-------------------------------------------"
# Test if we can login via web interface
HOMER_LOGIN=$(curl -s -X POST \
  -H "Content-Type: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"admin123\"}" \
  "http://localhost:9080/api/v3/auth" 2>/dev/null || echo "")

if [ -n "$HOMER_LOGIN" ]; then
  if echo "$HOMER_LOGIN" | grep -q "token\|apikey"; then
    echo "✅ Homer web interface authentication works"
    echo "   Login successful from host"
  else
    echo "⚠️  Homer authentication may have issues"
    echo "   Response: $(echo "$HOMER_LOGIN" | head -c 200)"
  fi
else
  echo "⚠️  Could not test web interface login"
fi
echo ""

echo "7. Checking API server logs for specific error..."
echo "-------------------------------------------"
# The error is "Error retrieving apikey"
API_SERVER_ERROR=$(sudo docker compose logs api-server --tail 100 | grep -i "Error retrieving apikey" | tail -5 || echo "")
if [ -n "$API_SERVER_ERROR" ]; then
  echo "Recent 'Error retrieving apikey' errors:"
  echo "$API_SERVER_ERROR"
  echo ""
  echo "This error means the API server cannot authenticate with Homer"
  echo "Possible causes:"
  echo "  1. Wrong username/password"
  echo "  2. Homer authentication endpoint not accessible"
  echo "  3. Homer user not created/activated"
fi
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""
echo "The 'Error retrieving apikey' error means API server can't authenticate with Homer"
echo ""
echo "Steps to fix:"
echo ""
echo "1. Verify Homer is accessible:"
echo "   curl http://localhost:9080"
echo "   Login in browser: admin / admin123"
echo ""
echo "2. Check if Homer user exists:"
echo "   - Open Homer UI: http://localhost:9080"
echo "   - Login: admin / admin123"
echo "   - Go to Settings → Users"
echo "   - Verify 'admin' user exists and is active"
echo ""
echo "3. If user doesn't exist, create it:"
echo "   - In Homer UI, go to Settings → Users"
echo "   - Add user: admin / admin123"
echo "   - Make sure user is active"
echo ""
echo "4. Test authentication manually:"
echo "   curl -X POST http://localhost:9080/api/v3/auth \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"username\":\"admin\",\"password\":\"admin123\"}'"
echo ""
echo "5. If authentication works, restart API server:"
echo "   sudo docker compose restart api-server"
echo ""
echo "6. Check API server logs again:"
echo "   sudo docker compose logs -f api-server"
echo ""

