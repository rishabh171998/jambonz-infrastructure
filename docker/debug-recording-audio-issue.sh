#!/bin/bash
# Script to debug why recording is still breaking audio

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
echo "Debugging Recording Audio Issue"
echo "=========================================="
echo ""

YOUR_ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

echo "=== Checking Account Recording Settings ==="
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null
SELECT 
  account_sid,
  name,
  record_all_calls,
  CASE 
    WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET'
    ELSE 'SET'
  END as bucket_status
FROM accounts 
WHERE account_sid IN ('$YOUR_ACCOUNT_SID', '$DEFAULT_ACCOUNT_SID')
ORDER BY account_sid;
EOF

echo ""
echo "=== Recent Feature Server Logs (Recording Related) ==="
echo ""
echo "Looking for recording task creation and audio issues..."
$DOCKER_CMD logs feature-server --tail 200 2>/dev/null | grep -E "(initiating Background task record|_initRecord|disableBidirectionalAudio|TaskListen|listen is being killed|audio|recording)" | tail -30

echo ""
echo "=== Recent API Server Logs (Recording Related) ==="
echo ""
echo "Looking for WebSocket connections and account checks..."
$DOCKER_CMD logs api-server --tail 200 2>/dev/null | grep -E "(record|bucket credential|close the socket|account)" | tail -20

echo ""
echo "=== Analysis ==="
echo ""
echo "The issue might be:"
echo "  1. Recording task with disableBidirectionalAudio:true is consuming audio"
echo "  2. Recording WebSocket is still closing (wrong account check)"
echo "  3. Recording task failure is killing the main audio stream"
echo ""
echo "Let's check if the recording task is being created at all..."

echo ""
echo "=== Checking if recording task is created for your account ==="
RECENT_CALLS=$($DOCKER_CMD logs feature-server --tail 500 2>/dev/null | grep -E "initiating Background task record" | grep "$YOUR_ACCOUNT_SID" | tail -1)

if [ -z "$RECENT_CALLS" ]; then
  echo "  ⚠️  No recording task found for your account in recent logs"
  echo "  This might mean recording is not being triggered"
else
  echo "  ✓ Found recording task for your account"
  echo "  $RECENT_CALLS"
fi

echo ""
echo "=== Checking API Server Account Resolution ==="
echo ""
echo "The API server might be using the wrong account_sid when checking"
echo "bucket credentials. Let's see what account it's checking..."

RECENT_WS=$($DOCKER_CMD logs api-server --tail 200 2>/dev/null | grep -E "does not have any bucket credential" | tail -1)

if [ -n "$RECENT_WS" ]; then
  echo "  Found: $RECENT_WS"
  if echo "$RECENT_WS" | grep -q "$DEFAULT_ACCOUNT_SID"; then
    echo "  ❌ API server is STILL checking default account!"
    echo "  This means the fix didn't work - the API server code"
    echo "  is hardcoded to use the default account."
  fi
else
  echo "  No recent 'bucket credential' errors found"
fi

echo ""
echo "=== Possible Solutions ==="
echo ""
echo "1. The API server code might be hardcoded to use default account"
echo "   → Need to check API server code or use Option 2 (copy credentials)"
echo ""
echo "2. disableBidirectionalAudio:true might be consuming the audio stream"
echo "   → This is a feature-server code issue"
echo ""
echo "3. Recording task failure is killing the main audio stream"
echo "   → This is a feature-server code issue"
echo ""

read -p "Try Option 2 (copy bucket credentials to default account)? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Copying bucket credentials to default account..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts a1
JOIN accounts a2 ON a2.account_sid = '$YOUR_ACCOUNT_SID'
SET a1.bucket_credential = a2.bucket_credential,
    a1.record_format = a2.record_format,
    a1.record_all_calls = 0
WHERE a1.account_sid = '$DEFAULT_ACCOUNT_SID';
EOF
  echo "✅ Bucket credentials copied to default account."
  echo "✅ Recording disabled for default account (to prevent conflicts)."
  echo ""
  echo "Restarting feature-server..."
  $DOCKER_CMD restart feature-server
  echo ""
  echo "✅ Done. Test a call now."
else
  echo ""
  echo "Skipped. The issue is likely in the API server or feature-server code."
  echo "You may need to:"
  echo "  1. Check the API server code to see why it uses default account"
  echo "  2. Check feature-server code for disableBidirectionalAudio behavior"
  echo "  3. Report this as a bug to jambonz"
fi

