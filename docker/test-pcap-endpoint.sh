#!/bin/bash
# Test PCAP endpoint to diagnose issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "PCAP Endpoint Diagnostic"
echo "=========================================="
echo ""

# Get account SID and a recent call
ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  echo "❌ Could not get account SID"
  exit 1
fi

echo "1. Account SID: $ACCOUNT_SID"
echo ""

# Get a recent call_sid
CALL_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT call_sid FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' AND call_sid IS NOT NULL ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$CALL_SID" ]; then
  echo "⚠️  No recent calls found with call_sid"
  echo ""
  echo "Trying to get sip_callid instead..."
  SIP_CALLID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_callid FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' AND sip_callid IS NOT NULL ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")
  if [ -n "$SIP_CALLID" ]; then
    echo "   Found sip_callid: $SIP_CALLID"
  fi
else
  echo "2. Call SID: $CALL_SID"
fi
echo ""

# Get API token
TOKEN=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "❌ Could not get API token"
  exit 1
fi

HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}

echo "3. Testing PCAP Endpoints..."
echo "-------------------------------------------"

# Test with call_sid and method
if [ -n "$CALL_SID" ]; then
  echo "Testing: /Accounts/$ACCOUNT_SID/RecentCalls/$CALL_SID/invite/pcap"
  HTTP_CODE=$(curl -s -o /tmp/pcap_test1.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${CALL_SID}/invite/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE"
  if [ "$HTTP_CODE" = "200" ]; then
    FILE_SIZE=$(stat -f%z /tmp/pcap_test1.txt 2>/dev/null || stat -c%s /tmp/pcap_test1.txt 2>/dev/null || echo "0")
    echo "   ✅ Success! File size: $FILE_SIZE bytes"
  elif [ "$HTTP_CODE" = "400" ]; then
    echo "   ❌ Bad Request"
    echo "   Response: $(head -c 200 /tmp/pcap_test1.txt 2>/dev/null || echo 'N/A')"
  elif [ "$HTTP_CODE" = "404" ]; then
    echo "   ⚠️  Not Found (PCAP may not be available for this call)"
  else
    echo "   ⚠️  Unexpected status"
    echo "   Response: $(head -c 200 /tmp/pcap_test1.txt 2>/dev/null || echo 'N/A')"
  fi
  echo ""
  
  # Test without method
  echo "Testing: /Accounts/$ACCOUNT_SID/RecentCalls/$CALL_SID/pcap (no method)"
  HTTP_CODE2=$(curl -s -o /tmp/pcap_test2.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${CALL_SID}/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE2"
  if [ "$HTTP_CODE2" = "200" ]; then
    echo "   ✅ Success without method parameter!"
  elif [ "$HTTP_CODE2" = "404" ]; then
    echo "   ⚠️  Route not found (method parameter may be required)"
  else
    echo "   Response: $(head -c 200 /tmp/pcap_test2.txt 2>/dev/null || echo 'N/A')"
  fi
  echo ""
fi

# Test with sip_callid if available
if [ -n "$SIP_CALLID" ] && [ -z "$CALL_SID" ]; then
  echo "Testing with sip_callid: /Accounts/$ACCOUNT_SID/RecentCalls/$SIP_CALLID/invite/pcap"
  HTTP_CODE3=$(curl -s -o /tmp/pcap_test3.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${SIP_CALLID}/invite/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE3"
  if [ "$HTTP_CODE3" = "200" ]; then
    echo "   ✅ Success with sip_callid!"
  else
    echo "   Response: $(head -c 200 /tmp/pcap_test3.txt 2>/dev/null || echo 'N/A')"
  fi
  echo ""
fi

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Based on the test results:"
echo "  - If /call_sid/invite/pcap returns 200: Method parameter IS required"
echo "  - If /call_sid/pcap returns 200: Method parameter is NOT required"
echo "  - If both return 404: Check API server logs for route definition"
echo ""

