#!/bin/bash
# Check if Swagger UI JavaScript files are accessible

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
echo "Checking Swagger UI JavaScript Files"
echo "=========================================="
echo ""

HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

BASE_URL="http://${HOST_IP}:3000/swagger"

# Files that should be accessible
FILES=(
  "swagger-ui.css"
  "swagger-ui-bundle.js"
  "swagger-ui-standalone-preset.js"
  "swagger-ui-init.js"
  "swagger.json"
  "favicon-32x32.png"
  "favicon-16x16.png"
)

echo "Testing files from: $BASE_URL"
echo ""

for FILE in "${FILES[@]}"; do
  URL="${BASE_URL}/${FILE}"
  echo -n "Testing: $FILE ... "
  
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$URL" 2>/dev/null || echo "000")
  CONTENT_TYPE=$(curl -s -o /dev/null -w "%{content_type}" -I "$URL" 2>/dev/null || echo "")
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ HTTP 200"
    if [ -n "$CONTENT_TYPE" ] && [ "$CONTENT_TYPE" != "text/html" ]; then
      echo "   Content-Type: $CONTENT_TYPE"
    fi
  elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ HTTP 404 (Not Found)"
    echo "   This file is missing - Swagger UI won't work!"
  elif [ "$HTTP_CODE" = "000" ]; then
    echo "❌ Connection failed"
  else
    echo "⚠️  HTTP $HTTP_CODE"
  fi
done

echo ""

# Check Swagger JSON for security definitions
echo "Checking Swagger JSON for security definitions:"
echo "-------------------------------------------"
SWAGGER_JSON=$(curl -s "${BASE_URL}/swagger.json" 2>/dev/null || echo "")

if [ -n "$SWAGGER_JSON" ]; then
  echo "✅ Swagger JSON is accessible"
  echo ""
  
  # Check for security definitions
  if echo "$SWAGGER_JSON" | grep -qi "securityDefinitions\|securitySchemes"; then
    echo "✅ Security definitions found in Swagger JSON"
    echo ""
    echo "Security configuration:"
    echo "$SWAGGER_JSON" | grep -i "securityDefinitions\|securitySchemes" -A 20 | head -30 | sed 's/^/   /'
  else
    echo "❌ NO security definitions in Swagger JSON"
    echo ""
    echo "This is why the Authorize button doesn't appear!"
    echo ""
    echo "The Swagger JSON needs to include security definitions like:"
    echo '  "securityDefinitions": {'
    echo '    "Bearer": {'
    echo '      "type": "apiKey",'
    echo '      "name": "Authorization",'
    echo '      "in": "header"'
    echo '    }'
    echo '  }'
  fi
else
  echo "❌ Swagger JSON not accessible"
fi

echo ""
echo "=========================================="
echo "Recommendations"
echo "=========================================="
echo ""

# Check which files are missing
MISSING_FILES=()
for FILE in "${FILES[@]}"; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "${BASE_URL}/${FILE}" 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" != "200" ]; then
    MISSING_FILES+=("$FILE")
  fi
done

if [ ${#MISSING_FILES[@]} -gt 0 ]; then
  echo "Missing files:"
  for FILE in "${MISSING_FILES[@]}"; do
    echo "  - $FILE"
  done
  echo ""
  echo "These files need to be served by the API server."
  echo "Check API server configuration or static file serving."
  echo ""
fi

if ! echo "$SWAGGER_JSON" | grep -qi "securityDefinitions\|securitySchemes"; then
  echo "To fix the missing Authorize button:"
  echo "  1. The API server needs to include security definitions in Swagger JSON"
  echo "  2. This is typically configured in the API server code"
  echo "  3. Alternative: Use API directly with curl (no Swagger UI needed)"
  echo ""
fi

echo "Use API directly with curl:"
echo "  curl -H \"Authorization: Bearer YOUR_TOKEN\" \\"
echo "       http://${HOST_IP}:3000/api/v1/Accounts"
echo ""

