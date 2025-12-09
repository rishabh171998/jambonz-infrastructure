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

# Make API call and save response
RESPONSE=$(curl -s -H "Authorization: Bearer $API_KEY" \
  "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "ERROR")

if [ "$RESPONSE" = "ERROR" ]; then
  echo "❌ Failed to connect to API"
  exit 1
fi

echo "Raw API Response:"
echo "$RESPONSE" | head -100
echo ""
echo "=========================================="
echo ""

# Check if it's valid JSON
if echo "$RESPONSE" | python3 -m json.tool > /dev/null 2>&1; then
  echo "✅ Response is valid JSON"
  echo ""
  
  # Extract and display structure
  echo "Response Structure:"
  echo "$RESPONSE" | python3 -c "
import json, sys
try:
    data = json.load(sys.stdin)
    print('Keys in response:', list(data.keys()))
    if 'data' in data:
        print('data type:', type(data['data']).__name__)
        if isinstance(data['data'], list):
            print('data length:', len(data['data']))
            if len(data['data']) > 0:
                print('First item keys:', list(data['data'][0].keys()) if isinstance(data['data'][0], dict) else 'Not a dict')
        else:
            print('data value:', data['data'])
    else:
        print('❌ No \"data\" key in response')
    if 'page' in data:
        print('page:', data['page'])
    if 'total' in data:
        print('total:', data['total'])
except Exception as e:
    print('Error parsing JSON:', e)
" 2>/dev/null || echo "Could not parse JSON structure"
else
  echo "❌ Response is not valid JSON"
  echo "This might be an error page or HTML response"
fi

echo ""
echo "=========================================="
echo "Checking API Server Logs for Errors"
echo "=========================================="
echo ""
$DOCKER_CMD logs api-server --tail 30 2>/dev/null | grep -i "error\|exception\|lcr" | tail -10 || echo "No recent errors found"
echo ""

