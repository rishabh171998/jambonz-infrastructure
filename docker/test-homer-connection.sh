#!/bin/bash
# Test Homer connection from API server

cd "$(dirname "$0")"

echo "=========================================="
echo "Test Homer Connection"
echo "=========================================="
echo ""

echo "1. Checking API server Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

echo "HOMER_BASE_URL: $HOMER_BASE_URL"
echo "HOMER_USERNAME: $HOMER_USERNAME"
echo "HOMER_PASSWORD: *** (configured: $([ -n "$HOMER_PASSWORD" ] && echo "yes" || echo "no"))"
echo ""

if [ "$HOMER_BASE_URL" = "http://homer:80" ]; then
  echo "✅ HOMER_BASE_URL is correct"
elif [ "$HOMER_BASE_URL" = "http://homer:9080" ]; then
  echo "❌ HOMER_BASE_URL is still wrong (should be http://homer:80)"
  echo "   Run: sudo docker compose up -d --force-recreate api-server"
else
  echo "⚠️  HOMER_BASE_URL: $HOMER_BASE_URL"
fi
echo ""

echo "2. Testing network connectivity..."
echo "-------------------------------------------"
# Test if API server can reach Homer
if sudo docker compose exec api-server ping -c 2 homer > /dev/null 2>&1; then
  echo "✅ API server can ping homer"
else
  echo "❌ API server cannot ping homer"
fi

# Test HTTP connection
HTTP_CODE=$(sudo docker compose exec api-server wget -q --spider -O- http://homer:80 2>&1 | grep -o "200 OK" || echo "")
if [ -n "$HTTP_CODE" ] || sudo docker compose exec api-server curl -s -o /dev/null -w "%{http_code}" http://homer:80 2>/dev/null | grep -q "200\|301\|302"; then
  echo "✅ API server can reach Homer HTTP (port 80)"
else
  echo "⚠️  Could not verify HTTP connection (may need curl/wget in container)"
fi
echo ""

echo "3. Checking Homer status..."
echo "-------------------------------------------"
HOMER_STATUS=$(sudo docker compose ps homer --format "{{.Status}}" 2>/dev/null || echo "")
echo "Homer status: $HOMER_STATUS"

if echo "$HOMER_STATUS" | grep -q "Up"; then
  # Test from host
  HOMER_HTTP=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
  if [ "$HOMER_HTTP" = "200" ] || [ "$HOMER_HTTP" = "301" ] || [ "$HOMER_HTTP" = "302" ]; then
    echo "✅ Homer web interface accessible from host (HTTP $HOMER_HTTP)"
    echo "   URL: http://localhost:9080"
  else
    echo "⚠️  Homer web interface not accessible from host (HTTP $HOMER_HTTP)"
  fi
fi
echo ""

echo "4. Checking for recent Homer connection attempts..."
echo "-------------------------------------------"
# Check last 100 lines for any Homer-related activity
HOMER_LOGS=$(sudo docker compose logs api-server --tail 100 | grep -iE "homer|pcap|getHomerApiKey" | tail -10 || echo "")
if [ -n "$HOMER_LOGS" ]; then
  echo "Recent Homer-related logs:"
  echo "$HOMER_LOGS"
else
  echo "✅ No Homer-related errors in recent logs"
  echo "   (This is good - means no connection errors)"
fi
echo ""

echo "5. Testing PCAP endpoint (if we have a call)..."
echo "-------------------------------------------"
ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"

# Get a recent call with sip_callid
CALL_INFO=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT call_sid, sip_callid
  FROM recent_calls 
  WHERE account_sid = '$ACCOUNT_SID' 
    AND sip_callid IS NOT NULL 
    AND sip_callid != ''
  ORDER BY attempted_at DESC 
  LIMIT 1;
" 2>/dev/null || echo "")

if [ -n "$CALL_INFO" ]; then
  SIP_CALLID=$(echo "$CALL_INFO" | awk '{print $2}')
  echo "Found call with SIP Call-ID: $SIP_CALLID"
  echo ""
  echo "To test PCAP:"
  echo "  1. Go to Recent Calls in webapp"
  echo "  2. Find a call"
  echo "  3. Click PCAP download button"
  echo "  4. Check API server logs: sudo docker compose logs api-server --tail 20"
else
  echo "⚠️  No recent calls found with sip_callid"
  echo "   Make a test call first, then try PCAP download"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if [ "$HOMER_BASE_URL" = "http://homer:80" ]; then
  echo "✅ Configuration looks correct"
  echo ""
  echo "Next steps:"
  echo "  1. Make a test call"
  echo "  2. Try downloading PCAP from Recent Calls page"
  echo "  3. If PCAP still doesn't work, check:"
  echo "     - Homer UI: http://localhost:9080 (login: admin/admin123)"
  echo "     - Check if call appears in Homer"
  echo "     - Check API server logs when clicking PCAP:"
  echo "       sudo docker compose logs -f api-server"
else
  echo "⚠️  Configuration needs to be fixed"
  echo "   Run: sudo docker compose up -d --force-recreate api-server"
fi
echo ""

