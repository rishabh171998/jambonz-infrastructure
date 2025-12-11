#!/bin/bash
# Test Swagger authentication and access

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
echo "Swagger Authentication Test"
echo "=========================================="
echo ""

HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

# 1. Test Swagger endpoint without auth
echo "1. Testing Swagger Endpoint (No Auth):"
echo "-------------------------------------------"
echo "   URL: http://${HOST_IP}:3000/swagger/"
SWAGGER_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://${HOST_IP}:3000/swagger/" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$SWAGGER_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
CONTENT=$(echo "$SWAGGER_RESPONSE" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: $HTTP_CODE"
if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ Swagger page loads (HTTP 200)"
  if echo "$CONTENT" | grep -q "<!DOCTYPE\|<html"; then
    echo "   ✅ Returns HTML"
    if echo "$CONTENT" | grep -qi "swagger"; then
      echo "   ✅ Contains Swagger UI"
    else
      echo "   ⚠️  HTML but no Swagger UI detected"
    fi
  fi
elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
  echo "   ⚠️  Authentication required (HTTP $HTTP_CODE)"
  echo "   This is normal - Swagger requires Bearer token"
elif [ "$HTTP_CODE" = "301" ] || [ "$HTTP_CODE" = "302" ]; then
  echo "   ⚠️  Redirect (HTTP $HTTP_CODE)"
else
  echo "   ❌ Unexpected status: $HTTP_CODE"
fi
echo ""

# 2. Test Swagger JSON
echo "2. Testing Swagger JSON:"
echo "-------------------------------------------"
echo "   URL: http://${HOST_IP}:3000/swagger/swagger.json"
SWAGGER_JSON=$(curl -s -w "\nHTTP_CODE:%{http_code}" "http://${HOST_IP}:3000/swagger/swagger.json" 2>/dev/null || echo "")
JSON_HTTP_CODE=$(echo "$SWAGGER_JSON" | grep "HTTP_CODE:" | cut -d: -f2)
JSON_CONTENT=$(echo "$SWAGGER_JSON" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: $JSON_HTTP_CODE"
if [ "$JSON_HTTP_CODE" = "200" ]; then
  echo "   ✅ Swagger JSON accessible"
  if echo "$JSON_CONTENT" | grep -q "\"swagger\"" || echo "$JSON_CONTENT" | grep -q "\"openapi\""; then
    echo "   ✅ Valid Swagger/OpenAPI JSON"
  fi
elif [ "$JSON_HTTP_CODE" = "401" ] || [ "$JSON_HTTP_CODE" = "403" ]; then
  echo "   ⚠️  Authentication required for JSON"
else
  echo "   ❌ Unexpected status: $JSON_HTTP_CODE"
fi
echo ""

# 3. Generate admin token
echo "3. Generating Admin Token:"
echo "-------------------------------------------"
echo "   Checking for admin token generation script..."

# Check if create-admin-token.sql exists
if [ -f "../jambonz-api-server/db/create-admin-token.sql" ]; then
  echo "   ✅ Found create-admin-token.sql"
  echo "   Run this to generate a token:"
  echo "   sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones < ../jambonz-api-server/db/create-admin-token.sql"
elif [ -f "mysql/create-admin-token.sql" ]; then
  echo "   ✅ Found create-admin-token.sql in mysql/"
  echo "   Run this to generate a token:"
  echo "   sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones < mysql/create-admin-token.sql"
else
  echo "   ⚠️  create-admin-token.sql not found"
  echo "   Creating token manually..."
  
  # Generate token using SQL
  TOKEN=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '-' || echo "")
  echo "   Generated token: $TOKEN"
  echo ""
  echo "   To create API key with this token, run:"
  echo "   sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e \""
  echo "   INSERT INTO api_keys (api_key_sid, token, account_sid, expires_at) VALUES"
  echo "   (UUID(), '$TOKEN', NULL, NULL);"
  echo "   \""
fi
echo ""

# 4. Test with authentication
echo "4. Testing with Authentication:"
echo "-------------------------------------------"
echo "   To test with Bearer token:"
echo "   curl -H \"Authorization: Bearer YOUR_TOKEN\" http://${HOST_IP}:3000/swagger/"
echo ""

# 5. Check API server logs
echo "5. API Server Logs (Swagger-related):"
echo "-------------------------------------------"
SWAGGER_LOGS=$($DOCKER_CMD logs --tail 50 api-server 2>/dev/null | grep -iE "swagger|/swagger" | tail -5 || echo "")
if [ -n "$SWAGGER_LOGS" ]; then
  echo "$SWAGGER_LOGS" | sed 's/^/   /'
else
  echo "   No Swagger-related logs found"
fi
echo ""

echo "=========================================="
echo "Solutions"
echo "=========================================="
echo ""
echo "1. If Swagger page is blank:"
echo "   - Open browser Developer Tools (F12)"
echo "   - Check Console tab for JavaScript errors"
echo "   - Check Network tab for failed requests"
echo ""
echo "2. If authentication is required:"
echo "   - Generate admin token using create-admin-token.sql"
echo "   - Use token in Swagger UI 'Authorize' button"
echo ""
echo "3. Alternative: Use API directly with curl:"
echo "   curl -H \"Authorization: Bearer YOUR_TOKEN\" \\"
echo "        http://${HOST_IP}:3000/api/v1/Accounts"
echo ""
echo "4. Check if Swagger UI files are loading:"
echo "   - Open Network tab in browser"
echo "   - Look for: swagger-ui.css, swagger-ui-bundle.js"
echo "   - Check if they return 200 or 404"
echo ""

