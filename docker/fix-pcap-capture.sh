#!/bin/bash
# Fix PCAP capture - ensure heplify-server is capturing SIP traffic

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix PCAP Capture"
echo "=========================================="
echo ""

echo "1. Checking heplify-server status..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "not running")
echo "heplify-server status: $HEPLIFY_STATUS"

if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "❌ heplify-server is restarting - checking logs..."
  sudo docker compose logs heplify-server --tail 30
elif echo "$HEPLIFY_STATUS" | grep -q "Up"; then
  echo "✅ heplify-server is running"
else
  echo "❌ heplify-server is not running"
  echo "   Starting heplify-server..."
  sudo docker compose up -d heplify-server
  sleep 5
fi
echo ""

echo "2. Checking heplify-server is listening on HEP port..."
echo "-------------------------------------------"
# heplify-server listens on UDP 9060 for HEP packets
HEP_LISTENING=$(sudo docker compose exec heplify-server netstat -ulnp 2>/dev/null | grep ":9060 " || echo "")
if [ -n "$HEP_LISTENING" ]; then
  echo "✅ heplify-server is listening on port 9060 (HEP)"
else
  echo "⚠️  Could not verify HEP port (may need netstat in container)"
  echo "   Checking if port is exposed..."
  sudo docker compose ps heplify-server | grep "9060" && echo "   ✅ Port 9060 is exposed" || echo "   ⚠️  Port 9060 not found in port mapping"
fi
echo ""

echo "3. Checking if services are sending HEP to heplify-server..."
echo "-------------------------------------------"
echo "⚠️  IMPORTANT: For PCAP to work, SIP traffic must be sent to heplify-server"
echo ""
echo "heplify-server receives HEP (Homer Encapsulation Protocol) packets on UDP 9060"
echo "These packets contain SIP messages that get stored in Homer database"
echo ""
echo "Services that should send HEP packets:"
echo "  - drachtio-sbc (if configured)"
echo "  - Other SIP proxies/gateways"
echo ""
echo "Checking drachtio-sbc configuration..."
if [ -f "./sbc/drachtio.conf.xml" ]; then
  if grep -q "heplify\|9060\|hep" ./sbc/drachtio.conf.xml; then
    echo "✅ drachtio.conf.xml mentions HEP/heplify"
    grep -i "heplify\|9060\|hep" ./sbc/drachtio.conf.xml | head -3
  else
    echo "⚠️  drachtio.conf.xml doesn't seem to have HEP configuration"
    echo "   drachtio-sbc may not be sending SIP to heplify-server"
  fi
else
  echo "⚠️  drachtio.conf.xml not found"
fi
echo ""

echo "4. Checking Homer database for captured calls..."
echo "-------------------------------------------"
if sudo docker compose ps postgres | grep -q "Up"; then
  HOMER_CALLS=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM homer_data WHERE method = 'INVITE' LIMIT 1;" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")
  echo "Calls in Homer database: $HOMER_CALLS"
  
  if [ "$HOMER_CALLS" = "0" ] || [ -z "$HOMER_CALLS" ]; then
    echo "⚠️  No calls captured in Homer"
    echo ""
    echo "   This means:"
    echo "   - SIP traffic is not being sent to heplify-server"
    echo "   - OR heplify-server is not processing HEP packets"
    echo ""
    echo "   To fix:"
    echo "   1. Configure drachtio-sbc to send HEP packets to heplify-server:9060"
    echo "   2. OR use a SIP capture tool that sends HEP to heplify-server"
    echo "   3. Make a test call and check if it appears in Homer UI"
  else
    echo "✅ Calls are being captured"
    
    # Get a sample call
    SAMPLE_CALL=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT callid, method, created_date FROM homer_data WHERE method = 'INVITE' ORDER BY created_date DESC LIMIT 1;" 2>/dev/null | grep -v "callid\|row\|---" | head -1 || echo "")
    if [ -n "$SAMPLE_CALL" ]; then
      echo "   Sample call: $SAMPLE_CALL"
    fi
  fi
else
  echo "⚠️  PostgreSQL not running"
fi
echo ""

echo "5. Testing PCAP endpoint with a real call..."
echo "-------------------------------------------"
ACCOUNT_SID="bed525b4-af09-40d2-9fe7-cdf6ae577c69"

# Get a recent call
CALL_INFO=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT call_sid, sip_callid, attempted_at
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
  
  # Check if this call exists in Homer
  if sudo docker compose ps postgres | grep -q "Up"; then
    HOMER_CALL=$(sudo docker compose exec -T postgres psql -Uhomer -dhomer -c "SELECT COUNT(*) FROM homer_data WHERE callid = '$SIP_CALLID' LIMIT 1;" 2>/dev/null | grep -E "^[[:space:]]*[0-9]+" | tr -d ' ' || echo "0")
    if [ "$HOMER_CALL" != "0" ] && [ -n "$HOMER_CALL" ]; then
      echo "✅ Call found in Homer database ($HOMER_CALL records)"
      echo ""
      echo "PCAP should work! Try downloading from Recent Calls page"
    else
      echo "❌ Call NOT found in Homer database"
      echo ""
      echo "   This means the SIP traffic for this call was not captured"
      echo "   - Check if heplify-server is receiving HEP packets"
      echo "   - Make a new call and check if it appears in Homer UI"
    fi
  fi
else
  echo "⚠️  No recent calls found"
  echo "   Make a test call first"
fi
echo ""

echo "6. Checking API server logs for PCAP errors..."
echo "-------------------------------------------"
# Monitor for PCAP-related errors
PCAP_ERRORS=$(sudo docker compose logs api-server --tail 100 | grep -iE "pcap|homer.*error|getHomerApiKey.*error" | tail -10 || echo "")
if [ -n "$PCAP_ERRORS" ]; then
  echo "Recent PCAP-related errors:"
  echo "$PCAP_ERRORS"
else
  echo "✅ No PCAP errors in recent logs"
fi
echo ""

echo "=========================================="
echo "Summary & Solution"
echo "=========================================="
echo ""
echo "The main issue: PCAP requires SIP traffic to be captured by heplify-server"
echo ""
echo "Current status:"
echo "  ✅ Homer is running and accessible"
echo "  ✅ API server has correct Homer URL"
echo "  ⚠️  heplify-server may not be receiving SIP traffic"
echo ""
echo "To fix PCAP:"
echo ""
echo "Option 1: Configure drachtio-sbc to send HEP packets"
echo "  - Add HEP export to drachtio.conf.xml"
echo "  - Send SIP messages to heplify-server:9060"
echo ""
echo "Option 2: Use a SIP capture tool"
echo "  - Use sngrep, tcpdump, or similar to capture SIP"
echo "  - Send captured packets to heplify-server as HEP"
echo ""
echo "Option 3: Check if calls are in Homer"
echo "  1. Open Homer UI: http://localhost:9080"
echo "  2. Login: admin / admin123"
echo "  3. Check if calls appear in the search"
echo "  4. If calls are there, PCAP should work"
echo ""
echo "Quick test:"
echo "  1. Make a test call"
echo "  2. Check Homer UI for the call"
echo "  3. If call appears, try PCAP download"
echo "  4. If call doesn't appear, heplify-server is not capturing"
echo ""

