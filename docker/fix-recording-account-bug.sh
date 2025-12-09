#!/bin/bash
# Script to fix the recording account bug
# The API server is checking the wrong account for bucket credentials

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
echo "Fixing Recording Account Bug"
echo "=========================================="
echo ""
echo "Problem: API server checks default account (9351f46a-...) for"
echo "bucket credentials instead of the actual call account."
echo ""
echo "This causes:"
echo "  1. Recording WebSocket to close immediately"
echo "  2. Main audio listen task to be killed"
echo "  3. No audio in calls when recording is enabled"
echo ""

YOUR_ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

echo "=== Current Account Status ==="
echo ""
echo "Your account ($YOUR_ACCOUNT_SID):"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null || echo "  Error querying"
SELECT 
  CONCAT('  record_all_calls: ', record_all_calls) as status,
  CONCAT('  bucket_credential: ', CASE WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET' ELSE 'SET' END) as bucket
FROM accounts 
WHERE account_sid = '$YOUR_ACCOUNT_SID';
EOF

echo ""
echo "Default account ($DEFAULT_ACCOUNT_SID):"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null || echo "  Error querying"
SELECT 
  CONCAT('  record_all_calls: ', record_all_calls) as status,
  CONCAT('  bucket_credential: ', CASE WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET' ELSE 'SET' END) as bucket
FROM accounts 
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF

echo ""
echo "=== Solution ==="
echo ""
echo "Option 1: Disable recording for default account (RECOMMENDED)"
echo "  This prevents the API server from checking wrong account"
echo ""
echo "Option 2: Copy bucket credentials to default account"
echo "  This is a workaround - not ideal but will work"
echo ""

read -p "Choose option (1/2): " -r
echo ""

case $REPLY in
  1)
    echo "Disabling recording for default account..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0 WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF
    echo "✅ Recording disabled for default account."
    echo ""
    echo "Ensuring recording is enabled for your account..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 1 WHERE account_sid = '$YOUR_ACCOUNT_SID';
EOF
    echo "✅ Recording enabled for your account."
    ;;
    
  2)
    echo "Copying bucket credentials from your account to default account..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts a1
JOIN accounts a2 ON a2.account_sid = '$YOUR_ACCOUNT_SID'
SET a1.bucket_credential = a2.bucket_credential,
    a1.record_format = a2.record_format
WHERE a1.account_sid = '$DEFAULT_ACCOUNT_SID';
EOF
    echo "✅ Bucket credentials copied to default account."
    ;;
    
  *)
    echo "Invalid option. Exiting."
    exit 1
    ;;
esac

echo ""
echo "Restarting feature-server..."
$DOCKER_CMD restart feature-server

echo ""
echo "✅ Done! Test a call now. Audio should work with recording enabled."
echo ""
echo "Note: This is a workaround. The real fix requires updating"
echo "the API server code to use the correct account_sid from the call."

