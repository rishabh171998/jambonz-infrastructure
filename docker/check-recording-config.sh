#!/bin/bash
# Script to check call recording configuration and diagnose why recordings aren't in S3

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
echo "Checking Call Recording Configuration"
echo "=========================================="
echo ""

# Get account SID
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")
if [ -z "$ACCOUNT_SID" ]; then
  ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")
fi

if [ -z "$ACCOUNT_SID" ]; then
  echo "ERROR: Could not find account SID"
  exit 1
fi

echo "Account SID: $ACCOUNT_SID"
echo ""

# Check account recording settings
echo "=== Account Recording Settings ==="
RECORD_ALL_CALLS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT record_all_calls FROM accounts WHERE account_sid = '$ACCOUNT_SID';" 2>/dev/null || echo "0")
RECORD_FORMAT=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT record_format FROM accounts WHERE account_sid = '$ACCOUNT_SID';" 2>/dev/null || echo "")
BUCKET_CREDENTIAL=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT bucket_credential FROM accounts WHERE account_sid = '$ACCOUNT_SID';" 2>/dev/null || echo "")

echo "  record_all_calls: $RECORD_ALL_CALLS"
echo "  record_format: $RECORD_FORMAT"

if [ -z "$BUCKET_CREDENTIAL" ] || [ "$BUCKET_CREDENTIAL" = "NULL" ]; then
  echo "  ❌ bucket_credential: NOT SET"
  echo ""
  echo "  ⚠️  WARNING: S3 bucket credentials are not configured!"
  echo "     Even if recording is enabled, files won't be uploaded to S3."
  echo "     Configure bucket credentials in the webapp: Accounts -> Edit Account -> Call Recording"
else
  echo "  ✅ bucket_credential: SET"
  # Try to parse the JSON to show details
  echo ""
  echo "  Bucket Credential Details:"
  echo "$BUCKET_CREDENTIAL" | python3 -c "
import json, sys
try:
    cred = json.load(sys.stdin)
    print(f\"    Vendor: {cred.get('vendor', 'N/A')}\")
    print(f\"    Bucket: {cred.get('name', 'N/A')}\")
    print(f\"    Region: {cred.get('region', 'N/A')}\")
    if 'endpoint' in cred:
        print(f\"    Endpoint: {cred.get('endpoint', 'N/A')}\")
except:
    print('    (Could not parse JSON)')
" 2>/dev/null || echo "    (Could not parse bucket credential JSON)"
fi

echo ""

# Check application recording settings
echo "=== Application Recording Settings ==="
APP_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT application_sid FROM applications WHERE account_sid = '$ACCOUNT_SID' LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$APP_SID" ]; then
  APP_RECORD_ALL=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT record_all_calls FROM applications WHERE application_sid = '$APP_SID';" 2>/dev/null || echo "0")
  echo "  Application SID: $APP_SID"
  echo "  Application record_all_calls: $APP_RECORD_ALL"
else
  echo "  ⚠️  No applications found for this account"
fi

echo ""

# Check if recording is actually enabled
if [ "$RECORD_ALL_CALLS" = "1" ] || [ "$RECORD_ALL_CALLS" = "true" ]; then
  echo "✅ Recording is ENABLED at account level"
elif [ -n "$APP_SID" ] && [ "$APP_RECORD_ALL" = "1" ]; then
  echo "✅ Recording is ENABLED at application level"
else
  echo "❌ Recording is NOT ENABLED"
  echo ""
  echo "   To enable recording:"
  echo "   1. Go to webapp: Accounts -> Edit Account"
  echo "   2. Enable 'Record all calls for this account'"
  echo "   3. Configure S3 bucket credentials"
  echo "   4. Save the account"
  exit 0
fi

echo ""

# Check recent calls to see if they should have recordings
echo "=== Recent Calls (last 5) ==="
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N <<EOF 2>/dev/null | while IFS=$'\t' read -r CALL_SID CALL_DATE; do
  echo "  Call SID: $CALL_SID"
  echo "  Date: $CALL_DATE"
  echo "  Expected S3 path: ${CALL_DATE:0:4}/${CALL_DATE:5:2}/${CALL_DATE:8:2}/$CALL_SID.${RECORD_FORMAT:-mp3}"
  echo ""
done
SELECT call_sid, DATE(attempted_at) as call_date
FROM (
  SELECT call_sid, attempted_at
  FROM recent_calls
  WHERE account_sid = '$ACCOUNT_SID'
  ORDER BY attempted_at DESC
  LIMIT 5
) AS recent
ORDER BY attempted_at DESC;
EOF

echo ""

# Check feature-server logs for recording-related errors
echo "=== Checking Feature Server Logs for Recording Errors ==="
$DOCKER_CMD logs feature-server --tail 100 2>/dev/null | grep -i "record\|s3\|bucket\|upload" | tail -10 || echo "  No recording-related errors found in feature-server logs"

echo ""

# Check API server logs for S3 upload errors and WebSocket connections
echo "=== Checking API Server Logs for Recording WebSocket & S3 Upload ==="
echo "  Looking for WebSocket connections and upload errors..."
$DOCKER_CMD logs api-server --tail 200 2>/dev/null | grep -i "record\|websocket\|ws\|s3\|bucket\|upload\|socket.*close\|no available record" | tail -15 || echo "  No recording-related messages found in API server logs"

echo ""

# Check feature-server logs for recording attempts
echo "=== Checking Feature Server Logs for Recording Attempts ==="
echo "  Looking for recording WebSocket connections and errors..."
$DOCKER_CMD logs feature-server --tail 200 2>/dev/null | grep -i "record\|websocket\|ws\|upload\|recording" | tail -15 || echo "  No recording-related messages found in feature-server logs"

echo ""

# Check when recording was enabled vs when calls were made
echo "=== Recording Timeline Check ==="
CALL_DATE=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT DATE(attempted_at) FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$CALL_DATE" ]; then
  echo "  Most recent call date: $CALL_DATE"
  echo "  ⚠️  IMPORTANT: Recording must be enabled BEFORE calls are made"
  echo "     If you enabled recording after $CALL_DATE, those calls won't have recordings"
fi

echo ""

echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="
echo ""
echo "Summary:"
if [ "$RECORD_ALL_CALLS" != "1" ] && [ "$RECORD_ALL_CALLS" != "true" ] && [ "$APP_RECORD_ALL" != "1" ]; then
  echo "  ❌ Recording is NOT enabled - enable it in the webapp"
  echo ""
  echo "  Steps to enable:"
  echo "    1. Go to webapp: Accounts -> Edit Account"
  echo "    2. Enable 'Record all calls for this account'"
  echo "    3. Configure S3 bucket credentials (vendor, bucket name, access keys)"
  echo "    4. Set recording format (mp3 or wav)"
  echo "    5. Save the account"
  echo "    6. Make a NEW test call (old calls won't be recorded)"
elif [ -z "$BUCKET_CREDENTIAL" ] || [ "$BUCKET_CREDENTIAL" = "NULL" ]; then
  echo "  ❌ S3 bucket credentials NOT configured"
  echo ""
  echo "  ⚠️  CRITICAL: Even if recording is enabled, files won't be uploaded to S3"
  echo "     without bucket credentials. The WebSocket will close immediately."
  echo ""
  echo "  Steps to configure:"
  echo "    1. Go to webapp: Accounts -> Edit Account -> Call Recording"
  echo "    2. Select bucket vendor (AWS S3, S3 Compatible, Google, Azure)"
  echo "    3. Enter bucket name, access key ID, secret access key"
  echo "    4. Enter region and endpoint (if S3 Compatible)"
  echo "    5. Save the account"
  echo "    6. Make a NEW test call"
else
  echo "  ✅ Recording is enabled"
  echo "  ✅ S3 bucket credentials are configured"
  echo ""
  echo "  If recordings still don't appear for NEW calls, check:"
  echo "    1. Feature server → API server WebSocket connection"
  echo "       Look for 'record upload' messages in feature-server logs"
  echo "    2. API server S3 upload errors"
  echo "       Look for 'pipeline error' or 'upload' errors in api-server logs"
  echo "    3. S3 bucket permissions"
  echo "       Verify IAM user/role has s3:PutObject permission"
  echo "    4. S3 bucket path format"
  echo "       Expected: YYYY/MM/DD/{callSid}.{format}"
  echo ""
  echo "  ⚠️  Note: Old calls made before recording was enabled won't have recordings"
fi
echo ""

