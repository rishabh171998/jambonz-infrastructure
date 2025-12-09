#!/bin/bash
# Script to investigate why recording is interfering with audio

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
echo "Investigating Recording Audio Conflict"
echo "=========================================="
echo ""

echo "The issue: When recording is enabled, the recording 'listen' task"
echo "is interfering with the main audio 'listen' task."
echo ""
echo "From the logs:"
echo "  1. Feature-server creates recording task with disableBidirectionalAudio:true"
echo "  2. Recording WebSocket connects then closes (wrong account check)"
echo "  3. Both recording AND main audio listen tasks get killed"
echo ""

echo "=== Checking Account Configuration ==="
ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

echo ""
echo "Your account ($ACCOUNT_SID):"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null | grep -E "(record_all_calls|bucket_credential)" || echo "  Error querying account"
SELECT 
  account_sid,
  name,
  record_all_calls,
  CASE 
    WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET'
    ELSE 'SET'
  END as bucket_status
FROM accounts 
WHERE account_sid = '$ACCOUNT_SID';
EOF

echo ""
echo "Default account ($DEFAULT_ACCOUNT_SID) - this is the one causing issues:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null | grep -E "(record_all_calls|bucket_credential)" || echo "  Error querying account"
SELECT 
  account_sid,
  name,
  record_all_calls,
  CASE 
    WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET'
    ELSE 'SET'
  END as bucket_status
FROM accounts 
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF

echo ""
echo "=== The Problem ==="
echo ""
echo "The API server is checking bucket credentials for the DEFAULT account"
echo "($DEFAULT_ACCOUNT_SID) instead of YOUR account ($ACCOUNT_SID)."
echo ""
echo "This causes the recording WebSocket to close immediately, which then"
echo "kills the main audio listen task."
echo ""
echo "=== Solution Options ==="
echo ""
echo "Option 1: Disable recording for the default account"
echo "  This prevents the API server from checking wrong account credentials"
echo ""
echo "Option 2: Add bucket credentials to the default account"
echo "  But this might not be what you want"
echo ""
echo "Option 3: Fix the API server to use the correct account SID"
echo "  This requires code changes in jambonz/api-server"
echo ""

read -p "Disable recording for default account? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Disabling recording for default account..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0 WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF
  echo "✅ Recording disabled for default account."
  echo ""
  echo "Now re-enable recording for YOUR account:"
  echo "  UPDATE accounts SET record_all_calls = 1 WHERE account_sid = '$ACCOUNT_SID';"
  echo ""
  read -p "Re-enable recording for your account now? (y/n) " -n 1 -r
  echo ""
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 1 WHERE account_sid = '$ACCOUNT_SID';
EOF
    echo "✅ Recording re-enabled for your account."
    echo ""
    echo "Restarting feature-server..."
    $DOCKER_CMD restart feature-server
    echo ""
    echo "✅ Done. Test a call now. Audio should work with recording enabled."
  fi
else
  echo ""
  echo "Skipped. You can manually fix this later."
fi

echo ""
echo "=========================================="
echo "Investigation Complete"
echo "=========================================="

