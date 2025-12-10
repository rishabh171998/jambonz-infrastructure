#!/bin/bash
# Check if recordings are being uploaded to S3

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
echo "Recording S3 Upload Check"
echo "=========================================="
echo ""

# 1. Check account bucket credentials
echo "1. Account Bucket Credentials:"
echo "-------------------------------------------"
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  echo "   Account SID: $ACCOUNT_SID"
  
  BUCKET_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT 
    account_sid,
    record_all_calls,
    record_format,
    bucket_credential IS NOT NULL as has_bucket_cred,
    enable_debug_log
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
  " 2>/dev/null || echo "")
  
  echo "$BUCKET_INFO" | tail -n +2 | while IFS=$'\t' read -r sid record_all record_format has_cred debug; do
    echo "   record_all_calls: $record_all"
    echo "   record_format: $record_format"
    if [ "$has_cred" = "1" ]; then
      echo "   bucket_credential: ✅ Configured"
    else
      echo "   bucket_credential: ❌ NOT configured"
      echo ""
      echo "   ⚠️  Recording will not work without bucket credentials"
      echo "   Configure in webapp: Account Settings → Enable call recording"
    fi
    echo "   enable_debug_log: $debug"
  done
else
  echo "   ⚠️  Could not find account"
fi
echo ""

# 2. Check WebSocket configuration
echo "2. Recording WebSocket Configuration:"
echo "-------------------------------------------"
FEATURE_WS=$($DOCKER_CMD exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL 2>/dev/null || echo "")
if [ -n "$FEATURE_WS" ]; then
  echo "   ✅ Feature-server: $FEATURE_WS"
else
  echo "   ❌ JAMBONZ_RECORD_WS_BASE_URL not set in feature-server"
fi
echo ""

# 3. Check recent recording activity
echo "3. Recent Recording Activity:"
echo "-------------------------------------------"
echo "   Feature Server (last 50 lines):"
RECORD_LOGS=$($DOCKER_CMD logs --tail 100 feature-server 2>/dev/null | grep -iE "record|recording|_initRecord" | tail -10 || echo "")
if [ -n "$RECORD_LOGS" ]; then
  echo "$RECORD_LOGS" | sed 's/^/   /'
else
  echo "   ⚠️  No recording activity found in logs"
fi
echo ""

# 4. Check S3 upload errors
echo "4. S3 Upload Errors:"
echo "-------------------------------------------"
echo "   Feature Server:"
S3_ERRORS_FS=$($DOCKER_CMD logs --tail 200 feature-server 2>/dev/null | grep -iE "s3|bucket|upload|error|fail" | tail -10 || echo "")
if [ -n "$S3_ERRORS_FS" ]; then
  echo "$S3_ERRORS_FS" | sed 's/^/   /'
else
  echo "   ✅ No S3 errors found in feature-server"
fi
echo ""

echo "   API Server:"
S3_ERRORS_API=$($DOCKER_CMD logs --tail 200 api-server 2>/dev/null | grep -iE "s3|bucket|upload|error|fail|recording" | tail -10 || echo "")
if [ -n "$S3_ERRORS_API" ]; then
  echo "$S3_ERRORS_API" | sed 's/^/   /'
else
  echo "   ✅ No S3 errors found in api-server"
fi
echo ""

# 5. Check WebSocket connection
echo "5. WebSocket Connection Status:"
echo "-------------------------------------------"
WS_CONN=$($DOCKER_CMD logs --tail 100 feature-server 2>/dev/null | grep -iE "websocket|ws://|record.*connect" | tail -5 || echo "")
if [ -n "$WS_CONN" ]; then
  echo "$WS_CONN" | sed 's/^/   /'
else
  echo "   ⚠️  No WebSocket connection logs found"
fi
echo ""

# 6. Check recent calls
echo "6. Recent Calls with Recording:"
echo "-------------------------------------------"
RECENT_CALLS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  call_sid,
  account_sid,
  from_number,
  to_number,
  created_at
FROM lcr 
WHERE account_sid = '$ACCOUNT_SID'
ORDER BY created_at DESC 
LIMIT 5;
" 2>/dev/null || echo "")

if [ -n "$RECENT_CALLS" ] && ! echo "$RECENT_CALLS" | grep -q "Empty set"; then
  echo "$RECENT_CALLS"
  echo ""
  echo "   Check if recordings exist for these calls in S3 bucket"
else
  echo "   ⚠️  No recent calls found"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "If recordings are not saving:"
echo "  1. Verify bucket credentials in webapp"
echo "  2. Check S3 bucket permissions"
echo "  3. Enable debug logging:"
echo "     UPDATE accounts SET enable_debug_log = 1 WHERE account_sid = '$ACCOUNT_SID';"
echo "  4. Make a test call and check logs:"
echo "     sudo docker compose logs -f feature-server | grep -i record"
echo ""

