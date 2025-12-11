#!/bin/bash
# Test PCAP endpoint - fixed version

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "PCAP Endpoint Diagnostic (Fixed)"
echo "=========================================="
echo ""

# Get account SID
ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$ACCOUNT_SID" ]; then
  ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")
fi

if [ -z "$ACCOUNT_SID" ]; then
  echo "❌ Could not get account SID"
  exit 1
fi

echo "1. Account SID: $ACCOUNT_SID"
echo ""

# Check recent_calls table structure
echo "2. Checking recent_calls table structure..."
echo "-------------------------------------------"
TABLE_COLS=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SHOW COLUMNS FROM recent_calls;" 2>/dev/null | awk '{print $1}' | tr '\n' ' ' || echo "")
echo "   Columns: $TABLE_COLS"
echo ""

# Get a recent call with all available fields
echo "3. Getting recent call data..."
echo "-------------------------------------------"
CALL_DATA=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT call_sid, sip_callid, account_sid, attempted_at FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$CALL_DATA" ]; then
  echo "❌ No recent calls found"
  echo ""
  echo "Checking if table exists and has data..."
  COUNT=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM recent_calls WHERE account_sid = '$ACCOUNT_SID';" 2>/dev/null || echo "0")
  echo "   Total calls for this account: $COUNT"
  exit 1
fi

# Parse the data
CALL_SID=$(echo "$CALL_DATA" | awk '{print $1}')
SIP_CALLID=$(echo "$CALL_DATA" | awk '{print $2}')
ATTEMPTED_AT=$(echo "$CALL_DATA" | awk '{print $4" "$5}')

echo "   Call SID: $CALL_SID"
echo "   SIP Call-ID: $SIP_CALLID"
echo "   Attempted at: $ATTEMPTED_AT"
echo ""

# Get API token
TOKEN=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
  echo "❌ Could not get API token"
  exit 1
fi

HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}

echo "4. Testing PCAP Endpoints..."
echo "-------------------------------------------"

# Test 1: With call_sid and method
if [ -n "$CALL_SID" ] && [ "$CALL_SID" != "NULL" ]; then
  echo "Test 1: /Accounts/$ACCOUNT_SID/RecentCalls/$CALL_SID/invite/pcap"
  HTTP_CODE1=$(curl -s -o /tmp/pcap_test1.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${CALL_SID}/invite/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE1"
  if [ "$HTTP_CODE1" = "200" ]; then
    FILE_SIZE=$(stat -f%z /tmp/pcap_test1.txt 2>/dev/null || stat -c%s /tmp/pcap_test1.txt 2>/dev/null || echo "0")
    echo "   ✅ Success! File size: $FILE_SIZE bytes"
  elif [ "$HTTP_CODE1" = "400" ]; then
    echo "   ❌ Bad Request"
    RESPONSE=$(head -c 500 /tmp/pcap_test1.txt 2>/dev/null || echo "N/A")
    echo "   Response: $RESPONSE"
  elif [ "$HTTP_CODE1" = "404" ]; then
    echo "   ⚠️  Not Found"
  else
    echo "   ⚠️  Status: $HTTP_CODE1"
    RESPONSE=$(head -c 200 /tmp/pcap_test1.txt 2>/dev/null || echo "N/A")
    echo "   Response: $RESPONSE"
  fi
  echo ""
  
  # Test 2: Without method
  echo "Test 2: /Accounts/$ACCOUNT_SID/RecentCalls/$CALL_SID/pcap (no method)"
  HTTP_CODE2=$(curl -s -o /tmp/pcap_test2.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${CALL_SID}/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE2"
  if [ "$HTTP_CODE2" = "200" ]; then
    echo "   ✅ Success without method parameter!"
  elif [ "$HTTP_CODE2" = "404" ]; then
    echo "   ⚠️  Route not found (method parameter may be required)"
  elif [ "$HTTP_CODE2" = "400" ]; then
    echo "   ❌ Bad Request"
    RESPONSE=$(head -c 200 /tmp/pcap_test2.txt 2>/dev/null || echo "N/A")
    echo "   Response: $RESPONSE"
  else
    echo "   ⚠️  Status: $HTTP_CODE2"
  fi
  echo ""
fi

# Test 3: With sip_callid if call_sid didn't work
if [ -n "$SIP_CALLID" ] && [ "$SIP_CALLID" != "NULL" ]; then
  echo "Test 3: /Accounts/$ACCOUNT_SID/RecentCalls/$SIP_CALLID/invite/pcap (using sip_callid)"
  HTTP_CODE3=$(curl -s -o /tmp/pcap_test3.txt -w "%{http_code}" \
    -H "Authorization: Bearer $TOKEN" \
    "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${SIP_CALLID}/invite/pcap" 2>/dev/null || echo "000")
  
  echo "   HTTP Status: $HTTP_CODE3"
  if [ "$HTTP_CODE3" = "200" ]; then
    echo "   ✅ Success with sip_callid!"
  elif [ "$HTTP_CODE3" = "400" ]; then
    echo "   ❌ Bad Request"
    RESPONSE=$(head -c 200 /tmp/pcap_test3.txt 2>/dev/null || echo "N/A")
    echo "   Response: $RESPONSE"
  else
    echo "   ⚠️  Status: $HTTP_CODE3"
  fi
  echo ""
fi

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
if [ "$HTTP_CODE1" = "200" ]; then
  echo "✅ Use: /Accounts/{sid}/RecentCalls/{call_sid}/invite/pcap"
elif [ "$HTTP_CODE2" = "200" ]; then
  echo "✅ Use: /Accounts/{sid}/RecentCalls/{call_sid}/pcap (no method)"
elif [ "$HTTP_CODE3" = "200" ]; then
  echo "✅ Use: /Accounts/{sid}/RecentCalls/{sip_callid}/invite/pcap (with sip_callid)"
else
  echo "⚠️  None of the endpoints returned 200"
  echo "   Check API server logs: sudo docker compose logs api-server | grep -i pcap"
fi
echo ""

