#!/bin/bash
# Verify Homer is working correctly

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Verify Homer is Working"
echo "=========================================="
echo ""

echo "1. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps postgres homer heplify-server
echo ""

echo "2. Testing Homer web interface..."
echo "-------------------------------------------"
HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer web interface is accessible (HTTP $HOMER_TEST)"
  echo "   URL: http://localhost:9080"
else
  echo "⚠️  Homer web interface not accessible (HTTP $HOMER_TEST)"
  echo "   Check logs: sudo docker compose logs homer"
fi
echo ""

echo "3. Checking API server Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

if [ -n "$HOMER_BASE_URL" ]; then
  echo "✅ HOMER_BASE_URL: $HOMER_BASE_URL"
else
  echo "❌ HOMER_BASE_URL not set"
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

echo "4. Testing PCAP endpoint (if API server has Homer config)..."
echo "-------------------------------------------"
if [ -n "$HOMER_BASE_URL" ] && [ -n "$HOMER_USERNAME" ]; then
  # Get account and call info
  ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")
  if [ -n "$ACCOUNT_SID" ]; then
    SIP_CALLID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_callid FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' AND sip_callid IS NOT NULL ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$SIP_CALLID" ]; then
      TOKEN=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")
      HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}
      
      echo "   Testing with sip_callid: $SIP_CALLID"
      HTTP_CODE=$(curl -s -o /tmp/pcap_test.txt -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${SIP_CALLID}/invite/pcap" 2>/dev/null || echo "000")
      
      if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ PCAP endpoint working! (HTTP 200)"
      elif [ "$HTTP_CODE" = "400" ]; then
        echo "   ⚠️  Bad Request (HTTP 400) - Check API server logs for Homer connection"
        RESPONSE=$(head -c 200 /tmp/pcap_test.txt 2>/dev/null || echo "N/A")
        echo "   Response: $RESPONSE"
      elif [ "$HTTP_CODE" = "404" ]; then
        echo "   ⚠️  Not Found (HTTP 404) - PCAP may not be available for this call"
      else
        echo "   ⚠️  Status: $HTTP_CODE"
      fi
    else
      echo "   ⚠️  No recent calls found to test"
    fi
  else
    echo "   ⚠️  Could not get account SID"
  fi
else
  echo "   ⚠️  API server not configured for Homer yet"
  echo "   Restart API server: sudo docker compose restart api-server"
fi
echo ""

echo "5. Checking recent Homer logs..."
echo "-------------------------------------------"
sudo docker compose logs homer --tail 10 | grep -E "info|error|panic" | tail -5 || echo "No recent logs"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer is running and accessible"
  echo ""
  echo "Next steps:"
  echo "  1. Access Homer UI: http://localhost:9080 (or http://15.207.113.122:9080)"
  echo "  2. Login with: admin / admin123 (or check Homer logs for default credentials)"
  echo "  3. Rebuild webapp: sudo docker compose build webapp"
  echo "  4. Restart webapp: sudo docker compose restart webapp"
  echo "  5. Test PCAP download in Recent Calls page"
else
  echo "⚠️  Homer may still be starting up"
  echo "   Wait a minute and check: sudo docker compose logs homer"
fi
echo ""

