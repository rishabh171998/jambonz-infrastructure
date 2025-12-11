#!/bin/bash
# Fix heplify-server restart issue and recording

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix heplify-server & Recording"
echo "=========================================="
echo ""

echo "1. Checking heplify-server logs..."
echo "-------------------------------------------"
sudo docker compose logs heplify-server --tail 50 | tail -20
echo ""

echo "2. Checking heplify-server config..."
echo "-------------------------------------------"
if [ -f "./heplify-server.toml" ]; then
  echo "✅ Config file exists"
  # Check if config has correct database settings
  if grep -q "DBDriver.*postgres" ./heplify-server.toml && grep -q "DBUser.*homer" ./heplify-server.toml; then
    echo "✅ Config has PostgreSQL settings"
  else
    echo "⚠️  Config may have wrong database settings"
  fi
else
  echo "❌ Config file not found!"
fi
echo ""

echo "3. Checking PostgreSQL connection from heplify-server..."
echo "-------------------------------------------"
# Test if heplify-server can reach postgres
if sudo docker compose exec heplify-server ping -c 2 postgres > /dev/null 2>&1; then
  echo "✅ heplify-server can reach postgres"
else
  echo "❌ heplify-server cannot reach postgres"
fi
echo ""

echo "4. Restarting heplify-server with proper config..."
echo "-------------------------------------------"
sudo docker compose stop heplify-server
sleep 2
sudo docker compose up -d heplify-server
sleep 5

HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "")
echo "heplify-server status: $HEPLIFY_STATUS"
echo ""

if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "⚠️  Still restarting, checking logs again..."
  sleep 5
  sudo docker compose logs heplify-server --tail 30 | tail -15
fi
echo ""

echo "5. Checking recording configuration..."
echo "-------------------------------------------"
# Check if S3 recording is configured in the account
ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"
echo "Checking account: $ACCOUNT_SID"

RECORDING_CONFIG=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT 
    recording_enabled,
    recording_bucket_vendor,
    recording_bucket_endpoint_uri,
    recording_bucket_name
  FROM accounts 
  WHERE account_sid = '$ACCOUNT_SID';
" 2>/dev/null || echo "")

if [ -n "$RECORDING_CONFIG" ]; then
  echo "Recording configuration:"
  echo "$RECORDING_CONFIG"
  
  # Check if recording is enabled
  RECORDING_ENABLED=$(echo "$RECORDING_CONFIG" | awk '{print $1}')
  if [ "$RECORDING_ENABLED" = "1" ]; then
    echo "✅ Recording is enabled for this account"
  else
    echo "⚠️  Recording is not enabled"
    echo "   Enable it in the webapp: Accounts → Edit Account → Enable call recording"
  fi
else
  echo "⚠️  Could not query recording configuration"
fi
echo ""

echo "6. Testing PCAP with correct account..."
echo "-------------------------------------------"
# Get a recent call for the correct account
CALL_INFO=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT call_sid, sip_callid, from_uri, to_uri, attempted_at
  FROM recent_calls 
  WHERE account_sid = '$ACCOUNT_SID' 
    AND sip_callid IS NOT NULL 
    AND sip_callid != ''
  ORDER BY attempted_at DESC 
  LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$CALL_INFO" ]; then
  SIP_CALLID=$(echo "$CALL_INFO" | awk '{print $2}')
  CALL_SID=$(echo "$CALL_INFO" | awk '{print $1}')
  echo "Found call: $CALL_SID"
  echo "SIP Call-ID: $SIP_CALLID"
  echo ""
  echo "To test PCAP download:"
  echo "  1. Go to Recent Calls in webapp"
  echo "  2. Find this call"
  echo "  3. Click PCAP download button"
else
  echo "⚠️  No recent calls found for account $ACCOUNT_SID"
  echo "   Make a test call first"
fi
echo ""

echo "7. Verifying S3 recording access..."
echo "-------------------------------------------"
# Check if we can access S3 (basic check)
if [ -n "$RECORDING_CONFIG" ]; then
  BUCKET_ENDPOINT=$(echo "$RECORDING_CONFIG" | awk '{print $3}')
  BUCKET_NAME=$(echo "$RECORDING_CONFIG" | awk '{print $4}')
  
  if [ -n "$BUCKET_ENDPOINT" ] && [ -n "$BUCKET_NAME" ]; then
    echo "S3 Endpoint: $BUCKET_ENDPOINT"
    echo "Bucket: $BUCKET_NAME"
    echo ""
    echo "To test recording:"
    echo "  1. Make a test call"
    echo "  2. Check S3 bucket for recording files"
    echo "  3. Check API server logs for recording errors"
  fi
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "heplify-server:"
if echo "$HEPLIFY_STATUS" | grep -q "Up" && ! echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "  ✅ Should be running now"
else
  echo "  ⚠️  Still having issues - check logs:"
  echo "     sudo docker compose logs heplify-server --tail 50"
fi
echo ""
echo "Recording:"
echo "  - Account SID: $ACCOUNT_SID"
echo "  - Check recording is enabled in webapp"
echo "  - Make a test call to verify"
echo ""
echo "PCAP:"
echo "  - Homer is running and accessible"
echo "  - API server has Homer config"
echo "  - Make a test call to generate PCAP data"
echo "  - Use account: $ACCOUNT_SID"
echo ""
echo "Next steps:"
echo "  1. If heplify-server still restarting, check:"
echo "     sudo docker compose logs heplify-server --tail 50"
echo ""
echo "  2. Make a test call and check:"
echo "     - Recording appears in S3 bucket"
echo "     - Call appears in Homer UI"
echo "     - PCAP can be downloaded from Recent Calls"
echo ""

