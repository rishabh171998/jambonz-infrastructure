#!/bin/bash
# Investigate why feature-server sends wrong account_sid to API server

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
echo "Investigating Account SID Bug"
echo "=========================================="
echo ""
echo "The problem: Feature-server sends wrong account_sid to API server"
echo ""

YOUR_ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

echo "=== Checking Call Session vs WebSocket Message ==="
echo ""
echo "Looking at recent call logs to see the mismatch..."
echo ""

echo "Feature-server logs (showing correct account_sid):"
$DOCKER_CMD logs feature-server --tail 100 2>/dev/null | grep -E "initiating Background task record|accountSid.*bed525b4" | tail -5

echo ""
echo "API server logs (showing wrong account_sid received):"
$DOCKER_CMD logs api-server --tail 100 2>/dev/null | grep -E "received JSON message from jambonz" | tail -1 | grep -o '"accountSid":"[^"]*"'

echo ""
echo "=== Checking Application Configuration ==="
echo ""
echo "The issue might be that the application is associated with"
echo "the default account instead of your account."
echo ""

APPLICATION_SID="08d78564-d3f6-4db4-95ce-513ae757c2c9"

echo "Application: $APPLICATION_SID"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null
SELECT 
  application_sid,
  name,
  account_sid,
  service_provider_sid,
  CASE 
    WHEN account_sid IS NULL THEN 'Service Provider Test App'
    ELSE 'Account-specific App'
  END as app_type
FROM applications 
WHERE application_sid = '$APPLICATION_SID';
EOF

echo ""
echo "=== The Real Issue ==="
echo ""
echo "Looking at the logs, feature-server correctly identifies your account"
echo "($YOUR_ACCOUNT_SID) but when it sends the WebSocket message to the"
echo "API server, it's using the default account ($DEFAULT_ACCOUNT_SID)."
echo ""
echo "This suggests the bug is in how feature-server constructs the"
echo "WebSocket message payload - it might be using the application's"
echo "service_provider_sid or default account instead of the call's account_sid."
echo ""
echo "=== Possible Root Causes ==="
echo ""
echo "1. Application is a service provider test app (account_sid is NULL)"
echo "   → Feature-server might be using service_provider's default account"
echo ""
echo "2. Feature-server code bug in _initRecord function"
echo "   → It might be using the wrong account_sid when building the message"
echo ""
echo "3. Call session has wrong account_sid set"
echo "   → The initial webhook might have set the wrong account"
echo ""

echo "=== Checking Initial Webhook ==="
echo ""
echo "Looking at the initial webhook to see what account_sid was set..."
$DOCKER_CMD logs feature-server --tail 200 2>/dev/null | grep -E "sending initial webhook|accountSid.*9351f46a" | tail -3

echo ""
echo "=== Solution ==="
echo ""
echo "The real fix requires checking the jambonz/feature-server code"
echo "to see why it's using the wrong account_sid when sending to API server."
echo ""
echo "For now, the ONLY workaround is to ensure the default account"
echo "has bucket credentials, OR disable recording entirely."
echo ""
echo "But you're right - this is wrong. The proper fix is in the code."

