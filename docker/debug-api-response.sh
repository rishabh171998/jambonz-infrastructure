#!/bin/bash

# Script to debug the API response structure for RecentCalls

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

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '\n' || echo "localhost")
else
  HOST_IP="localhost"
fi

# Get account SID
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")
fi

if [ -z "$ACCOUNT_SID" ]; then
  echo "ERROR: Could not find account SID"
  exit 1
fi

# Get API key
API_KEY=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys WHERE account_sid = '$ACCOUNT_SID' LIMIT 1;" 2>/dev/null || echo "")

echo "=========================================="
echo "Debugging RecentCalls API Response"
echo "=========================================="
echo ""
echo "Account SID: $ACCOUNT_SID"
echo "API Endpoint: http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25"
echo ""

# Verify API key exists and matches account
if [ -z "$API_KEY" ]; then
  echo "⚠️  No API key found for this account"
  echo "   Creating a test API key..."
  
  # Create API key via API (if possible) or directly in DB
  API_KEY=$(uuidgen | tr '[:upper:]' '[:lower:]' | tr -d '\n')
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO api_keys (api_key_sid, token, account_sid, created_at)
VALUES (UUID(), '$API_KEY', '$ACCOUNT_SID', NOW())
ON DUPLICATE KEY UPDATE token = '$API_KEY';
EOF
  echo "   Created API key: ${API_KEY:0:8}..."
else
  echo "✅ API key found: ${API_KEY:0:8}..."
  
  # Verify API key is not expired
  EXPIRED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM api_keys WHERE token = '$API_KEY' AND (expires_at IS NULL OR expires_at > NOW())" 2>/dev/null || echo "0")
  if [ "$EXPIRED" = "0" ]; then
    echo "⚠️  API key may be expired"
  fi
fi
echo ""

# Test without auth first to see the error
echo "Testing endpoint without authentication (to see error message)..."
NO_AUTH_CODE=$(curl -s -o /tmp/api_no_auth.json -w "%{http_code}" \
  "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "000")
NO_AUTH_RESPONSE=$(cat /tmp/api_no_auth.json 2>/dev/null || echo "")

if [ "$NO_AUTH_CODE" = "401" ] || [ "$NO_AUTH_CODE" = "403" ]; then
  echo "✅ Endpoint requires authentication (expected)"
else
  echo "⚠️  Endpoint returned: $NO_AUTH_CODE"
  echo "   Response: $NO_AUTH_RESPONSE"
fi
echo ""

# Make API call with authentication
echo "Testing with authentication..."
HTTP_CODE=$(curl -s -o /tmp/api_response.json -w "%{http_code}" \
  -H "Authorization: Bearer $API_KEY" \
  "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "000")

RESPONSE=$(cat /tmp/api_response.json 2>/dev/null || echo "ERROR")

if [ "$HTTP_CODE" = "000" ]; then
  echo "❌ Failed to connect to API"
  exit 1
fi

echo "HTTP Status Code: $HTTP_CODE"
echo ""

if [ "$HTTP_CODE" != "200" ]; then
  echo "⚠️  API returned non-200 status: $HTTP_CODE"
  echo ""
fi

echo "Raw API Response:"
echo "$RESPONSE" | head -100
echo ""
echo "=========================================="
echo ""

# Check if it's valid JSON
if [ "$HTTP_CODE" = "200" ] && echo "$RESPONSE" | python3 -m json.tool > /dev/null 2>&1; then
  echo "✅ Response is valid JSON"
  echo ""
  
  # Extract and display structure
  echo "Response Structure:"
  echo "$RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('Keys in response:', list(data.keys()))
    
    # Check for expected fields per OpenAPI spec
    expected_fields = ['total', 'batch', 'page', 'data']
    missing_fields = [f for f in expected_fields if f not in data]
    if missing_fields:
        print('⚠️  Missing expected fields:', missing_fields)
    
    # Check for unexpected fields
    if 'page_size' in data:
        print('⚠️  Found \"page_size\" but spec expects \"batch\"')
        print('   page_size value:', data['page_size'])
    
    if 'data' in data:
        print('data type:', type(data['data']).__name__)
        if isinstance(data['data'], list):
            print('✅ data is an array (length:', len(data['data']), ')')
            if len(data['data']) > 0:
                print('First item keys:', list(data['data'][0].keys()) if isinstance(data['data'][0], dict) else 'Not a dict')
        else:
            print('❌ data is NOT an array:', type(data['data']).__name__)
            print('   data value:', data['data'])
    else:
        print('❌ No \"data\" key in response')
    
    if 'page' in data:
        print('page:', data['page'], '(type:', type(data['page']).__name__, ')')
        if isinstance(data['page'], str):
            print('⚠️  page is a string, should be number per spec')
    if 'total' in data:
        print('total:', data['total'], '(type:', type(data['total']).__name__, ')')
    if 'batch' in data:
        print('batch:', data['batch'], '(type:', type(data['batch']).__name__, ')')
except Exception as e:
    print('Error parsing JSON:', e)
" 2>/dev/null || echo "Could not parse JSON structure"
else
  if [ "$HTTP_CODE" != "200" ]; then
    echo "❌ API returned HTTP $HTTP_CODE"
    echo "Response: $RESPONSE"
    echo ""
    echo "Common causes:"
    echo "  - 400 Bad Request: Missing required parameters or invalid request"
    echo "  - 401 Unauthorized: Invalid or missing API key"
    echo "  - 403 Forbidden: API key doesn't have permission"
    echo "  - 404 Not Found: Account not found"
  else
    echo "❌ Response is not valid JSON"
    echo "This might be an error page or HTML response"
  fi
fi

echo ""
echo "=========================================="
echo "Checking API Server Logs for Errors"
echo "=========================================="
echo ""
$DOCKER_CMD logs api-server --tail 30 2>/dev/null | grep -i "error\|exception\|lcr" | tail -10 || echo "No recent errors found"
echo ""

