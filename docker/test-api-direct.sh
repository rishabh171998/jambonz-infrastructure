#!/bin/bash
# Test API directly without Swagger UI

set -e

cd "$(dirname "$0")"

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

echo "=========================================="
echo "Testing API Directly (Without Swagger)"
echo "=========================================="
echo ""

HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

TOKEN="38700987-c7a4-4685-a5bb-af378f9734de"

echo "Token: $TOKEN"
echo "API Base URL: http://${HOST_IP}:3000/api/v1"
echo ""

# Test 1: Get Accounts
echo "1. Testing GET /api/v1/Accounts:"
echo "-------------------------------------------"
ACCOUNTS_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "http://${HOST_IP}:3000/api/v1/Accounts" 2>/dev/null || echo "")

HTTP_CODE=$(echo "$ACCOUNTS_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$ACCOUNTS_RESPONSE" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ Success!"
  echo ""
  echo "   Response (first 500 chars):"
  echo "$RESPONSE_BODY" | head -c 500
  echo ""
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  echo "   ❌ Authentication failed"
  echo "   Response: $RESPONSE_BODY"
  echo ""
  echo "   Check:"
  echo "   - Token is correct: $TOKEN"
  echo "   - Token exists in database"
else
  echo "   ⚠️  Unexpected status: $HTTP_CODE"
  echo "   Response: $RESPONSE_BODY"
fi
echo ""

# Test 2: Get Applications
echo "2. Testing GET /api/v1/Applications:"
echo "-------------------------------------------"
APPS_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
  -H "Authorization: Bearer $TOKEN" \
  "http://${HOST_IP}:3000/api/v1/Applications" 2>/dev/null || echo "")

HTTP_CODE=$(echo "$APPS_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
RESPONSE_BODY=$(echo "$APPS_RESPONSE" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ Success!"
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  echo "   ❌ Authentication failed"
else
  echo "   ⚠️  Status: $HTTP_CODE"
fi
echo ""

# Test 3: Verify token in database
echo "3. Verifying Token in Database:"
echo "-------------------------------------------"
TOKEN_CHECK=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT 
  api_key_sid,
  token,
  account_sid,
  service_provider_sid,
  expires_at,
  last_used
FROM api_keys 
WHERE token = '$TOKEN';
" 2>/dev/null || echo "")

if [ -n "$TOKEN_CHECK" ]; then
  echo "   ✅ Token found in database:"
  echo "$TOKEN_CHECK" | column -t | sed 's/^/   /'
else
  echo "   ❌ Token NOT found in database"
  echo "   Run: sudo ./check-and-fix-api-key.sh"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If API calls work with curl but Swagger UI doesn't show Authorize button:"
echo "  - The API server may not have Swagger authentication configured"
echo "  - Use curl/Postman instead of Swagger UI"
echo "  - Or check if Swagger JSON has securityDefinitions"
echo ""
echo "Useful curl commands:"
echo "  # List Accounts"
echo "  curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "       http://${HOST_IP}:3000/api/v1/Accounts"
echo ""
echo "  # List Applications"
echo "  curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "       http://${HOST_IP}:3000/api/v1/Applications"
echo ""
echo "  # Get Account Details"
echo "  curl -H \"Authorization: Bearer $TOKEN\" \\"
echo "       http://${HOST_IP}:3000/api/v1/Accounts/{account_sid}"
echo ""

