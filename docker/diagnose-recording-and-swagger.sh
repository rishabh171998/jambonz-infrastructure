#!/bin/bash
# Diagnose recording and swagger issues

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
echo "Recording & Swagger Diagnostic"
echo "=========================================="
echo ""

# 1. Check API Server Status
echo "1. API Server Status:"
echo "-------------------------------------------"
if $DOCKER_CMD ps | grep -q "api-server"; then
  echo "✅ API server is running"
  API_STATUS=$($DOCKER_CMD ps --format "table {{.Names}}\t{{.Status}}" | grep api-server)
  echo "   $API_STATUS"
else
  echo "❌ API server is NOT running"
fi
echo ""

# 2. Check API Server Port
echo "2. API Server Port Configuration:"
echo "-------------------------------------------"
API_PORT=$($DOCKER_CMD exec api-server printenv HTTP_PORT 2>/dev/null || echo "3000")
echo "   HTTP_PORT: ${API_PORT}"
echo ""

# 3. Check API Server Port Mapping
echo "3. API Server Port Mapping:"
echo "-------------------------------------------"
PORT_MAPPING=$($DOCKER_CMD ps --format "{{.Ports}}" | grep api-server || echo "")
if [ -n "$PORT_MAPPING" ]; then
  echo "   $PORT_MAPPING"
  if echo "$PORT_MAPPING" | grep -q "3000"; then
    echo "   ✅ Port 3000 is mapped"
  else
    echo "   ⚠️  Port 3000 may not be exposed"
  fi
else
  echo "   ⚠️  No port mapping found"
fi
echo ""

# 4. Test Swagger Endpoint
echo "4. Testing Swagger Endpoint:"
echo "-------------------------------------------"
HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

if [ -n "$HOST_IP" ]; then
  echo "   Testing: http://${HOST_IP}:3000/swagger"
  SWAGGER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger" 2>/dev/null || echo "000")
  if [ "$SWAGGER_RESPONSE" = "200" ]; then
    echo "   ✅ Swagger is accessible (HTTP 200)"
  elif [ "$SWAGGER_RESPONSE" = "000" ]; then
    echo "   ❌ Cannot connect to swagger (timeout/connection refused)"
    echo "   Check:"
    echo "     - Is port 3000 open in security group?"
    echo "     - Is API server listening on 0.0.0.0?"
  else
    echo "   ⚠️  Swagger returned HTTP $SWAGGER_RESPONSE"
  fi
else
  echo "   ⚠️  Could not determine HOST_IP"
fi
echo ""

# 5. Check Recording WebSocket Configuration
echo "5. Recording WebSocket Configuration:"
echo "-------------------------------------------"
FEATURE_WS_URL=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
FEATURE_WS_USER=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_USERNAME 2>/dev/null || echo "")
FEATURE_WS_PASS=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_PASSWORD 2>/dev/null || echo "")

API_WS_URL=$($DOCKER_CMD exec api-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
API_WS_USER=$($DOCKER_CMD exec api-server printenv JAMBONZ_RECORD_WS_USERNAME 2>/dev/null || echo "")
API_WS_PASS=$($DOCKER_CMD exec api-server printenv JAMBONZ_RECORD_WS_PASSWORD 2>/dev/null || echo "")

if [ -n "$FEATURE_WS_URL" ]; then
  echo "   Feature Server:"
  echo "     JAMBONZ_RECORD_WS_BASE_URL: $FEATURE_WS_URL"
  echo "     JAMBONZ_RECORD_WS_USERNAME: $FEATURE_WS_USER"
  echo "     JAMBONZ_RECORD_WS_PASSWORD: ${API_WS_PASS:+***}"
  if [ -z "$FEATURE_WS_URL" ] || [ -z "$FEATURE_WS_USER" ] || [ -z "$FEATURE_WS_PASS" ]; then
    echo "     ❌ Missing recording WebSocket configuration"
  else
    echo "     ✅ Recording WebSocket configured"
  fi
else
  echo "   ❌ JAMBONZ_RECORD_WS_BASE_URL not set in feature-server"
fi

if [ -n "$API_WS_URL" ]; then
  echo "   API Server:"
  echo "     JAMBONZ_RECORD_WS_BASE_URL: $API_WS_URL"
  echo "     JAMBONZ_RECORD_WS_USERNAME: $API_WS_USER"
  echo "     JAMBONZ_RECORD_WS_PASSWORD: ${API_WS_PASS:+***}"
  if [ -z "$API_WS_URL" ] || [ -z "$API_WS_USER" ] || [ -z "$API_WS_PASS" ]; then
    echo "     ❌ Missing recording WebSocket configuration"
  else
    echo "     ✅ Recording WebSocket configured"
  fi
else
  echo "   ⚠️  JAMBONZ_RECORD_WS_BASE_URL not set in api-server (may be optional)"
fi
echo ""

# 6. Check Account Recording Configuration
echo "6. Account Recording Configuration:"
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  echo "   Checking account: $ACCOUNT_SID"
  RECORD_CONFIG=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT 
    account_sid,
    record_all_calls,
    record_format,
    bucket_credential,
    enable_debug_log
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
  " 2>/dev/null || echo "")
  
  echo "$RECORD_CONFIG" | tail -n +2 | while IFS=$'\t' read -r sid record_all record_format bucket_cred debug; do
    echo "     record_all_calls: $record_all"
    echo "     record_format: $record_format"
    if [ -n "$bucket_cred" ] && [ "$bucket_cred" != "NULL" ]; then
      echo "     bucket_credential: ✅ Configured"
      # Parse bucket credential
      BUCKET_INFO=$(echo "$bucket_cred" | grep -oE '"vendor":"[^"]*"' | head -1 || echo "")
      if [ -n "$BUCKET_INFO" ]; then
        echo "       $BUCKET_INFO"
      fi
    else
      echo "     bucket_credential: ❌ NOT configured"
    fi
    echo "     enable_debug_log: $debug"
  done
else
  echo "   ⚠️  Could not find account"
fi
echo ""

# 7. Check Recent Recording Logs
echo "7. Recent Recording Activity:"
echo "-------------------------------------------"
echo "   Feature Server (last 20 lines with 'record'):"
$DOCKER_CMD logs --tail 50 feature-server 2>/dev/null | grep -i "record" | tail -5 || echo "   No recording logs found"
echo ""

echo "   API Server (last 20 lines with 'record'):"
$DOCKER_CMD logs --tail 50 api-server 2>/dev/null | grep -i "record" | tail -5 || echo "   No recording logs found"
echo ""

# 8. Check S3 Upload Errors
echo "8. S3 Upload Errors:"
echo "-------------------------------------------"
echo "   Feature Server:"
$DOCKER_CMD logs --tail 100 feature-server 2>/dev/null | grep -iE "(s3|bucket|upload|error)" | tail -5 || echo "   No S3-related logs found"
echo ""

echo "   API Server:"
$DOCKER_CMD logs --tail 100 api-server 2>/dev/null | grep -iE "(s3|bucket|upload|error)" | tail -5 || echo "   No S3-related logs found"
echo ""

# 9. Check API Server Listening
echo "9. API Server Network Status:"
echo "-------------------------------------------"
$DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "   ⚠️  Port 3000 not found in netstat"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Swagger Access:"
echo "  URL: http://${HOST_IP:-<HOST_IP>}:3000/swagger"
echo ""
echo "Recording Issues to Check:"
echo "  1. Bucket credentials configured in account?"
echo "  2. WebSocket connection between feature-server and api-server?"
echo "  3. S3 permissions correct?"
echo "  4. Recording format matches bucket vendor?"
echo ""

