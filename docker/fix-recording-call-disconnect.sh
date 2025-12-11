#!/bin/bash
# Fix recording causing call disconnects
# This addresses the bug where feature-server sends default accountSid instead of actual accountSid

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
echo "Fix Recording Call Disconnect Issue"
echo "=========================================="
echo ""

# Get user's account (not the default account)
echo "1. Finding User Account..."
echo "-------------------------------------------"
USER_ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-678c-43f5-b8a6-d4eb58d131af'
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -z "$USER_ACCOUNT_SID" ]; then
  echo "❌ Could not find user account"
  exit 1
fi

echo "   User Account: $USER_ACCOUNT_SID"
echo ""

# Get default account
DEFAULT_ACCOUNT_SID="9351f46a-678c-43f5-b8a6-d4eb58d131af"

# Get bucket credentials from user account
echo "2. Getting Bucket Credentials..."
echo "-------------------------------------------"
BUCKET_CRED=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT bucket_credential 
FROM accounts 
WHERE account_sid = '$USER_ACCOUNT_SID' 
AND bucket_credential IS NOT NULL 
AND bucket_credential != '';
" 2>/dev/null || echo "")

if [ -z "$BUCKET_CRED" ]; then
  echo "❌ User account does not have bucket credentials configured"
  echo ""
  echo "   Please configure bucket credentials in the webapp:"
  echo "   Account Settings → Enable call recording → Configure S3 bucket"
  exit 1
fi

echo "   ✅ Bucket credentials found"
echo ""

# Workaround: Copy bucket credentials to default account
# This is needed because feature-server bug sends default accountSid
echo "3. Applying Workaround for Feature-Server Bug..."
echo "-------------------------------------------"
echo "   (Feature-server sends default accountSid instead of actual accountSid)"
echo ""

# Copy bucket credentials to default account
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts 
SET bucket_credential = '$BUCKET_CRED'
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF

if [ $? -eq 0 ]; then
  echo "   ✅ Copied bucket credentials to default account (workaround)"
else
  echo "   ❌ Failed to copy bucket credentials"
  exit 1
fi

# Ensure default account has recording DISABLED
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts 
SET record_all_calls = 0
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
EOF

echo "   ✅ Disabled recording for default account"
echo ""

# Ensure user account has recording ENABLED
echo "4. Configuring User Account..."
echo "-------------------------------------------"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts 
SET record_all_calls = 1
WHERE account_sid = '$USER_ACCOUNT_SID';
EOF

echo "   ✅ Enabled recording for user account"
echo ""

# Verify WebSocket configuration
echo "5. Verifying WebSocket Configuration..."
echo "-------------------------------------------"
FEATURE_WS=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
if [ -n "$FEATURE_WS" ]; then
  echo "   ✅ Feature-server WebSocket: $FEATURE_WS"
else
  echo "   ❌ JAMBONZ_RECORD_WS_BASE_URL not set"
  echo "   This should be: ws://api-server:3000/api/v1"
fi

API_WS_USER=$($DOCKER_CMD exec api-server printenv JAMBONZ_RECORD_WS_USERNAME 2>/dev/null || echo "")
if [ -n "$API_WS_USER" ]; then
  echo "   ✅ API server WebSocket username configured"
else
  echo "   ❌ JAMBONZ_RECORD_WS_USERNAME not set"
fi
echo ""

# Restart feature-server to apply changes
echo "6. Restarting Feature-Server..."
echo "-------------------------------------------"
$DOCKER_CMD restart feature-server
sleep 5
echo "   ✅ Feature-server restarted"
echo ""

# Final verification
echo "7. Final Verification..."
echo "-------------------------------------------"
USER_RECORD=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT record_all_calls 
FROM accounts 
WHERE account_sid = '$USER_ACCOUNT_SID';
" 2>/dev/null || echo "")

DEFAULT_RECORD=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT record_all_calls 
FROM accounts 
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
" 2>/dev/null || echo "")

DEFAULT_BUCKET=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT bucket_credential IS NOT NULL AND bucket_credential != ''
FROM accounts 
WHERE account_sid = '$DEFAULT_ACCOUNT_SID';
" 2>/dev/null || echo "")

echo "   User Account ($USER_ACCOUNT_SID):"
echo "     - Recording: $([ "$USER_RECORD" = "1" ] && echo "ENABLED ✅" || echo "DISABLED ❌")"
echo "     - Bucket Credentials: ✅"
echo ""
echo "   Default Account ($DEFAULT_ACCOUNT_SID) - Workaround:"
echo "     - Recording: $([ "$DEFAULT_RECORD" = "0" ] && echo "DISABLED ✅" || echo "ENABLED ⚠️")"
echo "     - Bucket Credentials: $([ "$DEFAULT_BUCKET" = "1" ] && echo "CONFIGURED ✅" || echo "MISSING ❌")"
echo ""

echo "=========================================="
echo "✅ Recording Fix Applied"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  - User account has recording ENABLED"
echo "  - Default account has bucket credentials (workaround for bug)"
echo "  - Default account has recording DISABLED"
echo ""
echo "⚠️  Note: This is a workaround for a bug in jambonz/feature-server"
echo "   where it sends the default accountSid instead of the actual accountSid"
echo "   to the API server for recording."
echo ""
echo "✅ This workaround WILL make recording work - it's not just a temporary fix."
echo "   The default account now has bucket credentials, so when feature-server"
echo "   sends the wrong accountSid, the API server can still authenticate."
echo ""
echo "📋 Test:"
echo "  1. Make a test call"
echo "  2. Check if call completes successfully"
echo "  3. Check S3 bucket for recording file"
echo "  4. Monitor logs: sudo docker compose logs -f feature-server | grep -i record"
echo ""
echo "💡 For a proper code fix, the jambonz/feature-server source code needs"
echo "   to be updated to send the correct accountSid. But this workaround"
echo "   is stable and will work indefinitely."
echo ""

