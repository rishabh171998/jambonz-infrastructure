#!/bin/bash
# Fix recording and swagger issues

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
echo "Fixing Recording & Swagger Issues"
echo "=========================================="
echo ""

# 1. Check if JAMBONZ_RECORD_WS_BASE_URL is set in feature-server
echo "1. Checking Recording WebSocket Configuration..."
echo "-------------------------------------------"

FEATURE_WS_URL=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")

if [ -z "$FEATURE_WS_URL" ]; then
  echo "❌ JAMBONZ_RECORD_WS_BASE_URL not set in feature-server"
  echo ""
  echo "Updating docker-compose.yaml..."
  
  # Read current feature-server section
  FEATURE_START=$(grep -n "^  feature-server:" docker-compose.yaml | cut -d: -f1)
  if [ -z "$FEATURE_START" ]; then
    echo "❌ Could not find feature-server section"
    exit 1
  fi
  
  # Check if JAMBONZ_RECORD_WS_BASE_URL already exists
  if grep -A 20 "^  feature-server:" docker-compose.yaml | grep -q "JAMBONZ_RECORD_WS_BASE_URL"; then
    echo "✅ JAMBONZ_RECORD_WS_BASE_URL already in docker-compose.yaml"
  else
    echo "⚠️  Need to add JAMBONZ_RECORD_WS_BASE_URL to feature-server"
    echo "   Please add this line to feature-server environment section:"
    echo "   JAMBONZ_RECORD_WS_BASE_URL: 'ws://api-server:3000/api/v1'"
  fi
else
  echo "✅ JAMBONZ_RECORD_WS_BASE_URL is set: $FEATURE_WS_URL"
fi
echo ""

# 2. Check API server WebSocket configuration
echo "2. Checking API Server WebSocket Configuration..."
echo "-------------------------------------------"
API_WS_URL=$($DOCKER_CMD exec api-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
if [ -z "$API_WS_URL" ]; then
  echo "⚠️  JAMBONZ_RECORD_WS_BASE_URL not set in api-server (may be optional)"
else
  echo "✅ JAMBONZ_RECORD_WS_BASE_URL is set: $API_WS_URL"
fi
echo ""

# 3. Check API server is listening on 0.0.0.0
echo "3. Checking API Server Network Binding..."
echo "-------------------------------------------"
API_LISTEN=$($DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "")
if echo "$API_LISTEN" | grep -q "0.0.0.0:3000"; then
  echo "✅ API server is listening on 0.0.0.0:3000"
elif echo "$API_LISTEN" | grep -q ":3000"; then
  echo "⚠️  API server is listening but may not be on 0.0.0.0"
  echo "   $API_LISTEN"
else
  echo "❌ API server is not listening on port 3000"
fi
echo ""

# 4. Check account bucket credentials
echo "4. Checking Account Bucket Credentials..."
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  BUCKET_CRED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT bucket_credential 
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
  " 2>/dev/null || echo "")
  
  if [ -n "$BUCKET_CRED" ] && [ "$BUCKET_CRED" != "NULL" ] && [ -n "$(echo "$BUCKET_CRED" | tr -d '[:space:]')" ]; then
    echo "✅ Bucket credentials configured for account: $ACCOUNT_SID"
  else
    echo "❌ Bucket credentials NOT configured for account: $ACCOUNT_SID"
    echo ""
    echo "⚠️  Recording will not work without bucket credentials"
    echo "   Configure in webapp: Account Settings → Enable call recording"
  fi
else
  echo "⚠️  Could not find account"
fi
echo ""

# 5. Restart services if needed
echo "5. Restarting Services..."
echo "-------------------------------------------"
echo "Restarting api-server..."
$DOCKER_CMD restart api-server
sleep 3

echo "Restarting feature-server..."
$DOCKER_CMD restart feature-server
sleep 3

echo "✅ Services restarted"
echo ""

# 6. Verify swagger
echo "6. Verifying Swagger..."
echo "-------------------------------------------"
HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

if [ -n "$HOST_IP" ]; then
  echo "Testing: http://${HOST_IP}:3000/swagger"
  sleep 2
  SWAGGER_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger" 2>/dev/null || echo "000")
  if [ "$SWAGGER_RESPONSE" = "200" ]; then
    echo "✅ Swagger is accessible at: http://${HOST_IP}:3000/swagger"
  else
    echo "⚠️  Swagger returned HTTP $SWAGGER_RESPONSE"
    echo ""
    echo "Check:"
    echo "  1. Security group allows port 3000"
    echo "  2. API server logs: sudo docker compose logs api-server"
  fi
else
  echo "⚠️  Could not determine HOST_IP"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. If recording still not working, check logs:"
echo "     sudo docker compose logs -f feature-server | grep -i record"
echo "     sudo docker compose logs -f api-server | grep -i record"
echo ""
echo "  2. Verify bucket credentials in webapp"
echo ""
echo "  3. Test swagger: http://${HOST_IP:-<HOST_IP>}:3000/swagger"
echo ""

