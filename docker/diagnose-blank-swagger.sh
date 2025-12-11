#!/bin/bash
# Diagnose blank Swagger page issue

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
echo "Diagnosing Blank Swagger Page"
echo "=========================================="
echo ""

# 1. Check API server is running
echo "1. API Server Status:"
echo "-------------------------------------------"
if $DOCKER_CMD ps | grep -q "api-server"; then
  echo "✅ API server is running"
else
  echo "❌ API server is NOT running"
  exit 1
fi
echo ""

# 2. Test Swagger endpoint response
echo "2. Testing Swagger Endpoint:"
echo "-------------------------------------------"
HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

echo "Testing: http://${HOST_IP}:3000/swagger/"
echo ""

# Get full response
SWAGGER_RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}\nCONTENT_TYPE:%{content_type}\n" "http://${HOST_IP}:3000/swagger/" 2>/dev/null || echo "")

if [ -n "$SWAGGER_RESPONSE" ]; then
  HTTP_CODE=$(echo "$SWAGGER_RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
  CONTENT_TYPE=$(echo "$SWAGGER_RESPONSE" | grep "CONTENT_TYPE:" | cut -d: -f2)
  CONTENT=$(echo "$SWAGGER_RESPONSE" | sed '/HTTP_CODE:/d' | sed '/CONTENT_TYPE:/d')
  
  echo "   HTTP Status: $HTTP_CODE"
  echo "   Content-Type: $CONTENT_TYPE"
  echo ""
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ HTTP 200 OK"
    echo ""
    echo "   First 500 characters of response:"
    echo "$CONTENT" | head -c 500
    echo ""
    echo ""
    
    # Check if it's HTML
    if echo "$CONTENT" | grep -q "<!DOCTYPE\|<html"; then
      echo "   ✅ Response is HTML"
      
      # Check for Swagger UI
      if echo "$CONTENT" | grep -qi "swagger"; then
        echo "   ✅ Contains 'swagger' keyword"
      else
        echo "   ⚠️  Does not contain 'swagger' keyword"
      fi
      
      # Check for JavaScript errors
      if echo "$CONTENT" | grep -qi "error\|exception"; then
        echo "   ⚠️  Contains error/exception keywords"
      fi
    else
      echo "   ⚠️  Response is NOT HTML"
      echo "   Content preview: $CONTENT"
    fi
  else
    echo "   ❌ HTTP $HTTP_CODE (expected 200)"
  fi
else
  echo "   ❌ Could not connect to Swagger endpoint"
fi
echo ""

# 3. Check API server logs
echo "3. API Server Logs (last 30 lines):"
echo "-------------------------------------------"
$DOCKER_CMD logs --tail 30 api-server 2>/dev/null | tail -20
echo ""

# 4. Check for JavaScript/CORS errors
echo "4. Checking for Errors in Logs:"
echo "-------------------------------------------"
ERROR_LOGS=$($DOCKER_CMD logs --tail 100 api-server 2>/dev/null | grep -iE "error|exception|swagger|cors" | tail -10 || echo "")
if [ -n "$ERROR_LOGS" ]; then
  echo "$ERROR_LOGS" | sed 's/^/   /'
else
  echo "   ✅ No obvious errors in logs"
fi
echo ""

# 5. Test API endpoint directly
echo "5. Testing API Endpoint:"
echo "-------------------------------------------"
API_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:3000/api/v1" 2>/dev/null || echo "000")
if [ "$API_RESPONSE" = "200" ] || [ "$API_RESPONSE" = "401" ] || [ "$API_RESPONSE" = "403" ]; then
  echo "   ✅ API endpoint accessible (HTTP $API_RESPONSE)"
  echo "   (401/403 is expected without authentication)"
else
  echo "   ⚠️  API endpoint returned HTTP $API_RESPONSE"
fi
echo ""

# 6. Check if Swagger UI files are being served
echo "6. Testing Swagger JSON:"
echo "-------------------------------------------"
SWAGGER_JSON=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:3000/swagger/swagger.json" 2>/dev/null || echo "000")
if [ "$SWAGGER_JSON" = "200" ]; then
  echo "   ✅ Swagger JSON accessible"
else
  echo "   ⚠️  Swagger JSON returned HTTP $SWAGGER_JSON"
fi
echo ""

# 7. Check browser console simulation
echo "7. Common Causes of Blank Swagger Page:"
echo "-------------------------------------------"
echo "   1. JavaScript errors (check browser console)"
echo "   2. CORS issues"
echo "   3. Swagger UI not loading"
echo "   4. API server returning empty response"
echo "   5. Network/proxy issues"
echo ""

echo "=========================================="
echo "Recommendations"
echo "=========================================="
echo ""
echo "1. Open browser Developer Tools (F12)"
echo "   - Check Console tab for JavaScript errors"
echo "   - Check Network tab for failed requests"
echo ""
echo "2. Try accessing directly:"
echo "   http://${HOST_IP}:3000/swagger/swagger.json"
echo ""
echo "3. Check if API server is behind a proxy"
echo "   that might be interfering"
echo ""
echo "4. Try accessing from localhost:"
echo "   curl http://localhost:3000/swagger/"
echo ""

