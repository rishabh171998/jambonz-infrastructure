#!/bin/bash
# Comprehensive fix for PCAP download issue

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix PCAP Download Issue"
echo "=========================================="
echo ""

echo "1. Checking Homer status..."
echo "-------------------------------------------"
HOMER_STATUS=$(sudo docker compose ps homer --format "{{.Status}}" 2>/dev/null || echo "not running")
echo "Homer status: $HOMER_STATUS"

if echo "$HOMER_STATUS" | grep -q "Up"; then
  echo "✅ Homer is running"
  
  # Test Homer web interface
  HOMER_HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
  if [ "$HOMER_HTTP" = "200" ] || [ "$HOMER_HTTP" = "301" ] || [ "$HOMER_HTTP" = "302" ]; then
    echo "✅ Homer web interface accessible (HTTP $HOMER_HTTP)"
  else
    echo "⚠️  Homer web interface not accessible (HTTP $HOMER_HTTP)"
  fi
else
  echo "❌ Homer is not running"
  echo "   Starting Homer..."
  sudo docker compose up -d homer
  sleep 5
fi
echo ""

echo "2. Checking API server Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

if [ -n "$HOMER_BASE_URL" ]; then
  echo "✅ HOMER_BASE_URL: $HOMER_BASE_URL"
else
  echo "❌ HOMER_BASE_URL not set"
  echo "   Recreating API server..."
  sudo docker compose up -d --force-recreate api-server
  sleep 5
  HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
fi

if [ -n "$HOMER_USERNAME" ]; then
  echo "✅ HOMER_USERNAME: $HOMER_USERNAME"
else
  echo "❌ HOMER_USERNAME not set"
fi

if [ -n "$HOMER_PASSWORD" ]; then
  echo "✅ HOMER_PASSWORD: *** (configured)"
else
  echo "❌ HOMER_PASSWORD not set"
fi
echo ""

echo "3. Testing PCAP endpoint..."
echo "-------------------------------------------"
# Get a recent call with sip_callid
ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")
if [ -n "$ACCOUNT_SID" ]; then
  echo "Using account: $ACCOUNT_SID"
  
  # Get a recent call with sip_callid
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
    
    # Get API token
    TOKEN=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")
    HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}
    
    if [ -n "$TOKEN" ] && [ -n "$SIP_CALLID" ]; then
      # URL encode the sip_callid
      ENCODED_CALLID=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$SIP_CALLID'))" 2>/dev/null || echo "$SIP_CALLID")
      ENCODED_METHOD="invite"
      
      PCAP_URL="http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${ENCODED_CALLID}/${ENCODED_METHOD}/pcap"
      echo "Testing PCAP URL: $PCAP_URL"
      
      HTTP_CODE=$(curl -s -o /tmp/pcap_test_response.txt -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "$PCAP_URL" 2>/dev/null || echo "000")
      
      echo "HTTP Status: $HTTP_CODE"
      
      if [ "$HTTP_CODE" = "200" ]; then
        echo "✅ PCAP endpoint working!"
        PCAP_SIZE=$(wc -c < /tmp/pcap_test_response.txt 2>/dev/null || echo "0")
        echo "   PCAP file size: $PCAP_SIZE bytes"
      elif [ "$HTTP_CODE" = "400" ]; then
        echo "❌ Bad Request (400)"
        RESPONSE=$(head -c 200 /tmp/pcap_test_response.txt 2>/dev/null || echo "N/A")
        echo "   Response: $RESPONSE"
        echo ""
        echo "   Possible causes:"
        echo "   - Homer not configured correctly"
        echo "   - SIP Call-ID not found in Homer"
        echo "   - Check API server logs: sudo docker compose logs api-server | grep -i homer"
      elif [ "$HTTP_CODE" = "404" ]; then
        echo "⚠️  Not Found (404) - PCAP may not be available for this call"
        echo "   This is normal if the call wasn't captured by Homer"
      elif [ "$HTTP_CODE" = "500" ]; then
        echo "❌ Server Error (500)"
        RESPONSE=$(head -c 200 /tmp/pcap_test_response.txt 2>/dev/null || echo "N/A")
        echo "   Response: $RESPONSE"
        echo "   Check API server logs: sudo docker compose logs api-server --tail 50"
      else
        echo "⚠️  Unexpected status: $HTTP_CODE"
      fi
    else
      echo "⚠️  Missing token or SIP Call-ID"
    fi
  else
    echo "⚠️  No recent calls found with sip_callid"
    echo "   Make a test call to generate call data"
  fi
else
  echo "⚠️  Could not get account SID"
fi
echo ""

echo "4. Checking Homer database for captured calls..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  HOMER_CALLS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM homer_data WHERE method = 'INVITE' LIMIT 1;" 2>/dev/null | grep -E "[0-9]+" | head -1 || echo "0")
  echo "Calls in Homer database: $HOMER_CALLS"
  
  if [ "$HOMER_CALLS" = "0" ] || [ -z "$HOMER_CALLS" ]; then
    echo "⚠️  No calls captured in Homer yet"
    echo "   This is normal if:"
    echo "   - No calls have been made since Homer was set up"
    echo "   - heplify-server is not capturing SIP traffic"
    echo "   - SIP traffic is not being sent to heplify-server"
  fi
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "5. Checking heplify-server status..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "not running")
echo "heplify-server status: $HEPLIFY_STATUS"

if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "⚠️  heplify-server is restarting - check logs"
  sudo docker compose logs heplify-server --tail 20 | tail -10
elif echo "$HEPLIFY_STATUS" | grep -q "Up"; then
  echo "✅ heplify-server is running"
else
  echo "⚠️  heplify-server is not running"
  echo "   Starting heplify-server..."
  sudo docker compose up -d heplify-server
fi
echo ""

echo "6. Verifying webapp has PCAP fixes..."
echo "-------------------------------------------"
if [ -f "./jambonz-webapp-main/src/containers/internal/views/recent-calls/pcap.tsx" ]; then
  # Check if the fix is present (using sip_callid)
  if grep -q "sip_callid.*call_sid" ./jambonz-webapp-main/src/containers/internal/views/recent-calls/pcap.tsx; then
    echo "✅ Webapp has PCAP fix (using sip_callid)"
  else
    echo "⚠️  Webapp may not have PCAP fix"
    echo "   Rebuild webapp: sudo docker compose build webapp"
  fi
else
  echo "⚠️  PCAP component not found"
fi
echo ""

echo "=========================================="
echo "Summary & Next Steps"
echo "=========================================="
echo ""
echo "If PCAP is still not working:"
echo ""
echo "1. Verify Homer is accessible:"
echo "   curl http://localhost:9080"
echo "   Login: admin / admin123"
echo ""
echo "2. Check API server Homer connection:"
echo "   sudo docker compose logs api-server | grep -i homer"
echo ""
echo "3. Make a test call and check if it's captured:"
echo "   - Make a call"
echo "   - Check Homer UI for the call"
echo "   - Try downloading PCAP from Recent Calls page"
echo ""
echo "4. Rebuild webapp if needed:"
echo "   sudo docker compose build webapp"
echo "   sudo docker compose restart webapp"
echo ""
echo "5. Check heplify-server is capturing:"
echo "   sudo docker compose logs heplify-server --tail 50"
echo ""

