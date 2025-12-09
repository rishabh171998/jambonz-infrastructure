#!/bin/bash

# Script to test the RecentCalls API endpoint and diagnose issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Testing Recent Calls API"
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

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '\n' || echo "localhost")
else
  HOST_IP="localhost"
fi

# Get account SID from database
echo "Getting account SID from database..."
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  echo "❌ Could not find account SID in database"
  exit 1
fi

echo "Account SID: $ACCOUNT_SID"
echo ""

# Get API key for authentication
echo "Getting API key..."
API_KEY=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys WHERE account_sid = '$ACCOUNT_SID' LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$API_KEY" ]; then
  echo "⚠️  No API key found. Testing without authentication (will likely fail)..."
  AUTH_HEADER=""
else
  echo "API Key found: ${API_KEY:0:8}..."
  AUTH_HEADER="-H \"Authorization: Bearer $API_KEY\""
fi
echo ""

# Test RecentCalls endpoint
echo "=========================================="
echo "Testing RecentCalls API Endpoint"
echo "=========================================="
echo ""
echo "URL: http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25"
echo ""

# Make API call
if [ -n "$API_KEY" ]; then
  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    -H "Authorization: Bearer $API_KEY" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "ERROR: Connection failed")
else
  RESPONSE=$(curl -s -w "\nHTTP_CODE:%{http_code}" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "ERROR: Connection failed")
fi

HTTP_CODE=$(echo "$RESPONSE" | grep "HTTP_CODE:" | cut -d: -f2)
BODY=$(echo "$RESPONSE" | sed '/HTTP_CODE:/d')

echo "HTTP Status Code: $HTTP_CODE"
echo ""
echo "Response Body:"
echo "$BODY" | head -50
echo ""

# Check if response is valid JSON
if echo "$BODY" | jq . > /dev/null 2>&1; then
  echo "✅ Response is valid JSON"
  
  # Check for common error patterns
  if echo "$BODY" | jq -e '.msg' > /dev/null 2>&1; then
    ERROR_MSG=$(echo "$BODY" | jq -r '.msg')
    echo "❌ Error message: $ERROR_MSG"
  fi
  
  # Check if data array exists
  if echo "$BODY" | jq -e '.data' > /dev/null 2>&1; then
    DATA_TYPE=$(echo "$BODY" | jq -r 'type(.data)')
    echo "✅ 'data' field exists (type: $DATA_TYPE)"
    
    if [ "$DATA_TYPE" = "array" ]; then
      ARRAY_LENGTH=$(echo "$BODY" | jq '.data | length')
      echo "✅ 'data' is an array with $ARRAY_LENGTH items"
    else
      echo "⚠️  'data' is not an array (this might cause the forEach error)"
    fi
  else
    echo "❌ 'data' field is missing (this will cause the forEach error)"
  fi
  
  # Check for pagination
  if echo "$BODY" | jq -e '.page' > /dev/null 2>&1; then
    PAGE=$(echo "$BODY" | jq -r '.page')
    TOTAL=$(echo "$BODY" | jq -r '.total // "N/A"')
    echo "Pagination: page=$PAGE, total=$TOTAL"
  fi
else
  echo "⚠️  Response is not valid JSON"
  echo "This might indicate an error page or server issue"
fi

echo ""
echo "=========================================="
echo "Checking API Server Logs"
echo "=========================================="
echo ""
echo "Recent API server errors:"
$DOCKER_CMD logs api-server --tail 30 2>/dev/null | grep -i "error\|exception\|failed" | tail -10 || echo "No recent errors found"
echo ""

echo "=========================================="
echo "Checking Database for Call Records"
echo "=========================================="
echo ""

# Check if there are any call records in InfluxDB
echo "Checking InfluxDB for call records..."
CALL_COUNT=$($DOCKER_CMD exec -T influxdb influx -execute "SELECT COUNT(*) FROM calls" -database jambones -format json 2>/dev/null | jq -r '.[0].series[0].values[0][1] // "0"' || echo "0")

if [ "$CALL_COUNT" != "0" ] && [ "$CALL_COUNT" != "" ]; then
  echo "✅ Found $CALL_COUNT call records in InfluxDB"
else
  echo "⚠️  No call records found in InfluxDB (or database doesn't exist)"
  echo "   This is normal if you haven't made any calls yet"
fi
echo ""

echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""
echo "Common fixes:"
echo ""
echo "1. If 'data' field is missing or not an array:"
echo "   - Check API server logs: sudo docker compose logs api-server --tail 50"
echo "   - Verify InfluxDB is accessible: sudo docker compose exec influxdb influx -execute 'SHOW DATABASES'"
echo ""
echo "2. If getting 401/403 errors:"
echo "   - Check API key is valid"
echo "   - Verify authentication is working"
echo ""
echo "3. If getting 404 errors:"
echo "   - Check API server is running: sudo docker compose ps api-server"
echo "   - Verify endpoint exists in API server"
echo ""
echo "4. If forEach error persists:"
echo "   - The API might be returning null/undefined instead of empty array"
echo "   - Check API server code handles empty results correctly"
echo ""

