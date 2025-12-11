#!/bin/bash
# Complete fix for recording: enable and verify

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
echo "Complete Recording Fix"
echo "=========================================="
echo ""

# 1. Enable recording
echo "1. Enabling Recording..."
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  echo "❌ Could not find account"
  exit 1
fi

echo "Account SID: $ACCOUNT_SID"
echo ""

# Enable recording
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts 
SET record_all_calls = 1 
WHERE account_sid = '$ACCOUNT_SID';
EOF

if [ $? -eq 0 ]; then
  echo "✅ Recording enabled"
else
  echo "❌ Failed to enable recording"
  exit 1
fi
echo ""

# 2. Verify bucket credentials
echo "2. Verifying Bucket Credentials..."
echo "-------------------------------------------"
BUCKET_CRED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT bucket_credential IS NOT NULL 
FROM accounts 
WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

if [ "$BUCKET_CRED" = "1" ]; then
  echo "✅ Bucket credentials configured"
else
  echo "⚠️  Bucket credentials NOT configured"
  echo "   Configure in webapp: Account Settings → Enable call recording"
fi
echo ""

# 3. Verify WebSocket configuration
echo "3. Verifying WebSocket Configuration..."
echo "-------------------------------------------"
FEATURE_WS=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
if [ -n "$FEATURE_WS" ]; then
  echo "✅ Feature-server WebSocket: $FEATURE_WS"
else
  echo "❌ JAMBONZ_RECORD_WS_BASE_URL not set"
fi
echo ""

# 4. Restart services
echo "4. Restarting Services..."
echo "-------------------------------------------"
echo "Restarting feature-server..."
$DOCKER_CMD restart feature-server
sleep 5

echo "✅ Services restarted"
echo ""

# 5. Final verification
echo "5. Final Verification..."
echo "-------------------------------------------"
RECORD_STATUS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT record_all_calls 
FROM accounts 
WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

echo "Recording status: $RECORD_STATUS"
if [ "$RECORD_STATUS" = "1" ]; then
  echo "✅ Recording is ENABLED"
else
  echo "❌ Recording is DISABLED"
fi
echo ""

echo "=========================================="
echo "✅ Recording Fix Complete"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. Make a test call"
echo "  2. Check S3 bucket for recording file"
echo "  3. Monitor logs: sudo docker compose logs -f feature-server | grep -i record"
echo ""
echo "Note: If audio issues occur during recording, this is a known bug"
echo "      in jambonz/feature-server that requires a code fix."
echo ""

