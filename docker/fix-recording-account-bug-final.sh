#!/bin/bash
# Final fix: Copy bucket credentials to default account
# This is a workaround for the feature-server bug that sends wrong account_sid

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
echo "Fixing Recording Account Bug (Final Fix)"
echo "=========================================="
echo ""
echo "Problem: Feature-server is sending the DEFAULT account_sid"
echo "to the API server instead of the actual call account_sid."
echo ""
echo "This is a bug in jambonz/feature-server code."
echo ""
echo "Workaround: Copy bucket credentials to default account"
echo "so the API server check will pass."
echo ""

YOUR_ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

echo "=== Current Status ==="
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null
SELECT 
  CONCAT('Account: ', name, ' (', account_sid, ')') as info,
  CONCAT('  record_all_calls: ', record_all_calls) as recording,
  CONCAT('  bucket_credential: ', CASE WHEN bucket_credential IS NULL OR bucket_credential = '' THEN 'NOT SET' ELSE 'SET' END) as bucket
FROM accounts 
WHERE account_sid IN ('$YOUR_ACCOUNT_SID', '$DEFAULT_ACCOUNT_SID')
ORDER BY account_sid;
EOF

echo ""
echo "=== Applying Workaround ==="
echo ""
echo "Copying bucket credentials from your account to default account..."
echo "This will allow the API server check to pass."
echo ""

$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts a1
JOIN accounts a2 ON a2.account_sid = '$YOUR_ACCOUNT_SID'
SET a1.bucket_credential = a2.bucket_credential,
    a1.record_format = a2.record_format
WHERE a1.account_sid = '$DEFAULT_ACCOUNT_SID';
EOF

echo "✅ Bucket credentials copied to default account."
echo ""
echo "Keeping recording disabled for default account to prevent conflicts..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0 WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
UPDATE accounts SET record_all_calls = 1 WHERE account_sid = '$YOUR_ACCOUNT_SID';
EOF

echo "✅ Recording settings updated."
echo ""
echo "Restarting feature-server..."
$DOCKER_CMD restart feature-server

echo ""
echo "✅ Done! Test a call now. Audio should work with recording enabled."
echo ""
echo "⚠️  IMPORTANT: This is a workaround for a bug in jambonz/feature-server"
echo "   where it sends the wrong account_sid to the API server."
echo ""
echo "   The real fix requires updating jambonz/feature-server code to"
echo "   send the correct account_sid from the call context."
echo ""
echo "   You should report this bug to the jambonz team."

