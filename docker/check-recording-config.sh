#!/bin/bash
# Check recording configuration for the account

cd "$(dirname "$0")"

ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"

echo "=========================================="
echo "Recording Configuration Check"
echo "=========================================="
echo ""

echo "1. Checking account recording settings..."
echo "-------------------------------------------"
RECORDING_CONFIG=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT 
    account_sid,
    name,
    recording_enabled,
    recording_bucket_vendor,
    recording_bucket_endpoint_uri,
    recording_bucket_name,
    recording_bucket_access_key_id,
    recording_bucket_secret_access_key IS NOT NULL as has_secret
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

if [ -n "$RECORDING_CONFIG" ]; then
  echo "$RECORDING_CONFIG" | awk '{
    print "Account SID: " $1
    print "Account Name: " $2
    print "Recording Enabled: " $3
    print "Bucket Vendor: " $4
    print "Endpoint URI: " $5
    print "Bucket Name: " $6
    print "Access Key ID: " $7
    print "Has Secret: " $8
  }'
else
  echo "❌ Could not query account"
fi
echo ""

echo "2. Checking API server recording configuration..."
echo "-------------------------------------------"
# Check if API server has S3 credentials or recording config
echo "Checking API server environment..."
sudo docker compose exec api-server printenv | grep -iE "s3|recording|bucket" | head -5 || echo "No S3/recording env vars found"
echo ""

echo "3. Checking recent calls with recording..."
echo "-------------------------------------------"
RECORDED_CALLS=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT 
    call_sid,
    from_uri,
    to_uri,
    recording_url,
    attempted_at
  FROM recent_calls 
  WHERE account_sid = '$ACCOUNT_SID'
    AND attempted_at > DATE_SUB(NOW(), INTERVAL 24 HOUR)
  ORDER BY attempted_at DESC 
  LIMIT 5;
" 2>/dev/null || echo "")

if [ -n "$RECORDED_CALLS" ]; then
  echo "Recent calls:"
  echo "$RECORDED_CALLS" | while IFS=$'\t' read -r call_sid from_uri to_uri recording_url attempted_at; do
    echo "  Call: $call_sid"
    if [ -n "$recording_url" ] && [ "$recording_url" != "NULL" ]; then
      echo "    ✅ Has recording: $recording_url"
    else
      echo "    ⚠️  No recording URL"
    fi
  done
else
  echo "⚠️  No recent calls found"
fi
echo ""

echo "4. Checking API server logs for recording errors..."
echo "-------------------------------------------"
sudo docker compose logs api-server --tail 100 | grep -iE "recording|s3|bucket|error" | tail -10 || echo "No recording-related errors found"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If recording is not working:"
echo "  1. Verify recording is enabled in webapp for this account"
echo "  2. Check S3 credentials are correct"
echo "  3. Verify S3 bucket exists and is accessible"
echo "  4. Make a test call and check API server logs"
echo "  5. Check S3 bucket for recording files"
echo ""
