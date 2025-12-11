#!/bin/bash
# Complete fix for Homer setup

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Complete Homer Setup Fix"
echo "=========================================="
echo ""

echo "1. Recreating API server with Homer config..."
echo "-------------------------------------------"
sudo docker compose up -d --force-recreate api-server
sleep 5
echo "✅ API server recreated"
echo ""

echo "1b. Restarting heplify-server with config..."
echo "-------------------------------------------"
sudo docker compose up -d --force-recreate heplify-server
sleep 3
echo "✅ heplify-server restarted"
echo ""

echo "2. Verifying API server Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

if [ -n "$HOMER_BASE_URL" ]; then
  echo "✅ HOMER_BASE_URL: $HOMER_BASE_URL"
else
  echo "❌ HOMER_BASE_URL not set - check docker-compose.yaml"
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

echo "3. Checking Homer web interface..."
echo "-------------------------------------------"
sleep 5
HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer web interface is accessible (HTTP $HOMER_TEST)"
else
  echo "⚠️  Homer web interface not accessible (HTTP $HOMER_TEST)"
  echo "   Checking Homer logs..."
  sudo docker compose logs homer --tail 20 | tail -10
fi
echo ""

echo "4. Checking heplify-server..."
echo "-------------------------------------------"
HEPLIFY_STATUS=$(sudo docker compose ps heplify-server --format "{{.Status}}" 2>/dev/null || echo "")
if echo "$HEPLIFY_STATUS" | grep -q "Restarting"; then
  echo "⚠️  heplify-server is restarting"
  echo "   Checking logs..."
  sudo docker compose logs heplify-server --tail 20 | tail -10
  echo ""
  echo "   heplify-server may need a config file. Checking..."
  # heplify-server might need a TOML config file
else
  echo "✅ heplify-server status: $HEPLIFY_STATUS"
fi
echo ""

echo "5. Testing PCAP endpoint..."
echo "-------------------------------------------"
if [ -n "$HOMER_BASE_URL" ] && [ -n "$HOMER_USERNAME" ]; then
  ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")
  if [ -n "$ACCOUNT_SID" ]; then
    SIP_CALLID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT sip_callid FROM recent_calls WHERE account_sid = '$ACCOUNT_SID' AND sip_callid IS NOT NULL ORDER BY attempted_at DESC LIMIT 1;" 2>/dev/null || echo "")
    if [ -n "$SIP_CALLID" ]; then
      TOKEN=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT token FROM api_keys LIMIT 1;" 2>/dev/null || echo "")
      HOST_IP=${HOST_IP:-$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "localhost")}
      
      echo "   Testing PCAP endpoint..."
      HTTP_CODE=$(curl -s -o /tmp/pcap_test.txt -w "%{http_code}" \
        -H "Authorization: Bearer $TOKEN" \
        "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls/${SIP_CALLID}/invite/pcap" 2>/dev/null || echo "000")
      
      if [ "$HTTP_CODE" = "200" ]; then
        echo "   ✅ PCAP endpoint working! (HTTP 200)"
      elif [ "$HTTP_CODE" = "400" ]; then
        RESPONSE=$(head -c 200 /tmp/pcap_test.txt 2>/dev/null || echo "N/A")
        echo "   ⚠️  Bad Request (HTTP 400)"
        echo "   Response: $RESPONSE"
        echo "   Check API server logs: sudo docker compose logs api-server | grep -i homer"
      else
        echo "   ⚠️  Status: $HTTP_CODE"
      fi
    fi
  fi
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If Homer env vars are still missing:"
echo "  1. Check docker-compose.yaml has HOMER_* vars in api-server section"
echo "  2. Recreate: sudo docker compose up -d --force-recreate api-server"
echo ""
echo "If Homer web interface not accessible:"
echo "  1. Wait a minute for initialization"
echo "  2. Check logs: sudo docker compose logs homer"
echo "  3. Try: curl http://localhost:9080"
echo ""
echo "Next: Rebuild webapp and test PCAP download"
echo "  sudo docker compose build webapp"
echo "  sudo docker compose restart webapp"
echo ""

