#!/bin/bash
# Enable recording for account

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
echo "Enabling Recording for Account"
echo "=========================================="
echo ""

# Get account SID
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

# Check current status
CURRENT_STATUS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT record_all_calls 
FROM accounts 
WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

echo "Current record_all_calls: $CURRENT_STATUS"
echo ""

if [ "$CURRENT_STATUS" = "1" ]; then
  echo "✅ Recording is already enabled"
else
  echo "Enabling recording..."
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
fi

echo ""

# Verify bucket credentials
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

# Restart feature-server to apply changes
echo "Restarting feature-server..."
$DOCKER_CMD restart feature-server
sleep 3

echo ""
echo "=========================================="
echo "✅ Recording Enabled"
echo "=========================================="
echo ""
echo "Note: If you still experience audio issues during recording,"
echo "      this is a known bug in jambonz/feature-server"
echo "      that requires a code fix."
echo ""

