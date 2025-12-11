#!/bin/bash
# Diagnose why Swagger UI isn't showing Authorize button

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
echo "Diagnosing Swagger UI Issue"
echo "=========================================="
echo ""

HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

# 1. Test Swagger endpoint and get full response
echo "1. Testing Swagger Endpoint:"
echo "-------------------------------------------"
echo "   URL: http://${HOST_IP}:3000/swagger/"
echo ""

SWAGGER_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\n" "http://${HOST_IP}:3000/swagger/" 2>/dev/null || echo "")
HTTP_CODE=$(echo "$SWAGGER_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
CONTENT=$(echo "$SWAGGER_RESPONSE" | sed '/HTTP_CODE:/d')

echo "   HTTP Status: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" = "200" ]; then
  echo "   ✅ HTTP 200 OK"
  echo ""
  
  # Check if it's HTML
  if echo "$CONTENT" | grep -q "<!DOCTYPE\|<html"; then
    echo "   ✅ Response is HTML"
    echo ""
    
    # Check for Swagger UI elements
    echo "   Checking for Swagger UI elements:"
    if echo "$CONTENT" | grep -qi "swagger-ui"; then
      echo "   ✅ Contains 'swagger-ui'"
    else
      echo "   ❌ Missing 'swagger-ui'"
    fi
    
    if echo "$CONTENT" | grep -qi "swagger-ui-bundle"; then
      echo "   ✅ Contains 'swagger-ui-bundle'"
    else
      echo "   ❌ Missing 'swagger-ui-bundle'"
    fi
    
    if echo "$CONTENT" | grep -qi "swagger-ui-standalone"; then
      echo "   ✅ Contains 'swagger-ui-standalone'"
    else
      echo "   ❌ Missing 'swagger-ui-standalone'"
    fi
    
    # Check for security definitions
    if echo "$CONTENT" | grep -qi "securityDefinitions\|securitySchemes"; then
      echo "   ✅ Contains security definitions"
    else
      echo "   ⚠️  No security definitions found"
    fi
    
    # Check for authorize button
    if echo "$CONTENT" | grep -qi "authorize\|lock"; then
      echo "   ✅ Contains authorize/lock references"
    else
      echo "   ⚠️  No authorize button references found"
    fi
    
    # Check for JavaScript errors in content
    if echo "$CONTENT" | grep -qi "error\|exception"; then
      echo "   ⚠️  Contains error/exception keywords"
    fi
    
    echo ""
    echo "   First 1000 characters of HTML:"
    echo "$CONTENT" | head -c 1000
    echo ""
    echo ""
  else
    echo "   ⚠️  Response is NOT HTML"
    echo "   Content preview: $(echo "$CONTENT" | head -c 200)"
  fi
else
  echo "   ❌ HTTP $HTTP_CODE (expected 200)"
fi
echo ""

# 2. Test Swagger JSON
echo "2. Testing Swagger JSON:"
echo "-------------------------------------------"
SWAGGER_JSON=$(curl -s "http://${HOST_IP}:3000/swagger/swagger.json" 2>/dev/null || echo "")
if [ -n "$SWAGGER_JSON" ]; then
  echo "   ✅ Swagger JSON accessible"
  
  # Check for security definitions in JSON
  if echo "$SWAGGER_JSON" | grep -qi "securityDefinitions\|securitySchemes"; then
    echo "   ✅ Security definitions found in JSON"
    echo ""
    echo "   Security definitions:"
    echo "$SWAGGER_JSON" | grep -i "securityDefinitions\|securitySchemes" -A 10 | head -20 | sed 's/^/   /'
  else
    echo "   ⚠️  No security definitions in Swagger JSON"
    echo "   This is why the Authorize button isn't showing!"
  fi
else
  echo "   ❌ Swagger JSON not accessible"
fi
echo ""

# 3. Check API server logs
echo "3. API Server Logs (Swagger-related):"
echo "-------------------------------------------"
SWAGGER_LOGS=$($DOCKER_CMD logs --tail 100 api-server 2>/dev/null | grep -iE "swagger|/swagger" | tail -10 || echo "")
if [ -n "$SWAGGER_LOGS" ]; then
  echo "$SWAGGER_LOGS" | sed 's/^/   /'
else
  echo "   No Swagger-related logs found"
fi
echo ""

# 4. Check if Swagger UI files are accessible
echo "4. Testing Swagger UI Static Files:"
echo "-------------------------------------------"
STATIC_FILES=(
  "swagger-ui.css"
  "swagger-ui-bundle.js"
  "swagger-ui-standalone-preset.js"
)

for FILE in "${STATIC_FILES[@]}"; do
  FILE_URL="http://${HOST_IP}:3000/swagger/${FILE}"
  FILE_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$FILE_URL" 2>/dev/null || echo "000")
  if [ "$FILE_STATUS" = "200" ]; then
    echo "   ✅ $FILE - HTTP 200"
  else
    echo "   ❌ $FILE - HTTP $FILE_STATUS"
  fi
done
echo ""

# 5. Check browser console simulation
echo "5. Common Issues:"
echo "-------------------------------------------"
echo "   If Swagger UI loads but no Authorize button:"
echo "   1. Swagger JSON missing securityDefinitions"
echo "   2. API server not configured for authentication"
echo "   3. Swagger UI version doesn't support auth"
echo ""
echo "   If Swagger UI doesn't load at all:"
echo "   1. JavaScript files not loading (check Network tab)"
echo "   2. CORS issues"
echo "   3. Browser console errors"
echo ""

echo "=========================================="
echo "Recommendations"
echo "=========================================="
echo ""
echo "1. Open browser Developer Tools (F12):"
echo "   - Console tab: Check for JavaScript errors"
echo "   - Network tab: Check which files are failing to load"
echo ""
echo "2. Check Swagger JSON for security definitions:"
echo "   curl http://${HOST_IP}:3000/swagger/swagger.json | grep -i security"
echo ""
echo "3. If security definitions are missing:"
echo "   - The API server may not be configured for Swagger auth"
echo "   - You may need to use API directly with curl instead"
echo ""
echo "4. Try accessing API directly:"
echo "   curl -H \"Authorization: Bearer YOUR_TOKEN\" \\"
echo "        http://${HOST_IP}:3000/api/v1/Accounts"
echo ""

