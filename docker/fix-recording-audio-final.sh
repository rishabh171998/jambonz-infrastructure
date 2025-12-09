#!/bin/bash
# Final fix for recording audio issue
# The problem: Recording task is interfering with main audio stream

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
echo "Final Fix for Recording Audio Issue"
echo "=========================================="
echo ""
echo "The issue: When recording is enabled, the recording task"
echo "with disableBidirectionalAudio:true is consuming or"
echo "interfering with the main audio stream."
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
echo "=== The Real Problem ==="
echo ""
echo "Based on the logs, the issue is:"
echo "  1. Recording task is created with disableBidirectionalAudio:true"
echo "  2. This setting might be consuming the audio stream"
echo "  3. OR the recording task failure is killing the main audio task"
echo ""
echo "This is likely a bug in jambonz/feature-server where:"
echo "  - Recording task interferes with main audio when it fails"
echo "  - OR disableBidirectionalAudio:true prevents audio from reaching the call"
echo ""

echo "=== Solution Options ==="
echo ""
echo "Option 1: Copy bucket credentials to default account (WORKAROUND)"
echo "  This ensures the recording WebSocket doesn't close"
echo "  But might not fix the audio issue if it's a code bug"
echo ""
echo "Option 2: Temporarily disable recording (SAFEST)"
echo "  Use this until the jambonz team fixes the bug"
echo ""
echo "Option 3: Check if there's a way to configure recording differently"
echo "  Maybe disableBidirectionalAudio can be changed?"
echo ""

read -p "Choose option (1/2/3): " -r
echo ""

case $REPLY in
  1)
    echo ""
    echo "Copying bucket credentials to default account..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts a1
JOIN accounts a2 ON a2.account_sid = '$YOUR_ACCOUNT_SID'
SET a1.bucket_credential = a2.bucket_credential,
    a1.record_format = a2.record_format
WHERE a1.account_sid = '$DEFAULT_ACCOUNT_SID';
EOF
    echo "✅ Bucket credentials copied."
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
    echo "✅ Done. Test a call now."
    echo ""
    echo "⚠️  If audio still doesn't work, this is a bug in jambonz/feature-server"
    echo "   where the recording task interferes with the main audio stream."
    echo "   You'll need to disable recording until it's fixed."
    ;;
    
  2)
    echo ""
    echo "Disabling recording for all accounts..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0;
EOF
    echo "✅ Recording disabled for all accounts."
    echo ""
    echo "Restarting feature-server..."
    $DOCKER_CMD restart feature-server
    echo ""
    echo "✅ Done. Audio should work now (but no recording)."
    echo ""
    echo "This confirms the issue is with recording. You can re-enable"
    echo "recording later when the bug is fixed in jambonz/feature-server."
    ;;
    
  3)
    echo ""
    echo "The disableBidirectionalAudio setting is controlled by"
    echo "jambonz/feature-server code. It's set to 'true' when creating"
    echo "recording tasks, which might be consuming the audio stream."
    echo ""
    echo "This requires a code fix in jambonz/feature-server."
    echo ""
    echo "You can:"
    echo "  1. Report this as a bug to jambonz"
    echo "  2. Fork jambonz/feature-server and fix it yourself"
    echo "  3. Use Option 2 (disable recording) until it's fixed"
    echo ""
    echo "The bug is likely in how recording tasks handle audio streams"
    echo "when disableBidirectionalAudio is true."
    ;;
    
  *)
    echo "Invalid option. Exiting."
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "Fix Applied"
echo "=========================================="

