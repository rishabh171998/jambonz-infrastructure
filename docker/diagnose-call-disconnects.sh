#!/bin/bash
# Diagnose call disconnect issues

cd "$(dirname "$0")"

echo "=========================================="
echo "Call Disconnect Diagnostics"
echo "=========================================="
echo ""

echo "1. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps drachtio-sbc rtpengine api-server
echo ""

echo "2. Checking recent call records..."
echo "-------------------------------------------"
RECENT_CALLS=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT 
    call_sid,
    from_uri,
    to_uri,
    call_status,
    attempted_at,
    TIMESTAMPDIFF(SECOND, attempted_at, answered_at) as duration
  FROM recent_calls 
  ORDER BY attempted_at DESC 
  LIMIT 5;
" 2>/dev/null || echo "")

if [ -n "$RECENT_CALLS" ]; then
  echo "$RECENT_CALLS"
  echo ""
  echo "Checking for failed/disconnected calls..."
  FAILED_CALLS=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
    SELECT COUNT(*) 
    FROM recent_calls 
    WHERE call_status = 'failed' 
    AND attempted_at > DATE_SUB(NOW(), INTERVAL 1 HOUR);
  " 2>/dev/null || echo "0")
  echo "Failed calls in last hour: $FAILED_CALLS"
else
  echo "⚠️  Could not query call records"
fi
echo ""

echo "3. Checking RTPEngine connectivity..."
echo "-------------------------------------------"
RTPENGINE_IP=$(sudo docker compose exec -T rtpengine hostname -i 2>/dev/null | tr -d '[:space:]' || echo "")
if [ -n "$RTPENGINE_IP" ]; then
  echo "RTPEngine IP: $RTPENGINE_IP"
  echo "Testing RTPEngine ping..."
  sudo docker compose exec rtpengine rtpengine-ctl ping 2>/dev/null && echo "✅ RTPEngine responding" || echo "⚠️  RTPEngine not responding"
else
  echo "⚠️  Could not get RTPEngine IP"
fi
echo ""

echo "4. Checking drachtio-sbc logs for errors..."
echo "-------------------------------------------"
sudo docker compose logs drachtio-sbc --tail 50 | grep -iE "error|failed|timeout|disconnect|bye" | tail -10 || echo "No errors found"
echo ""

echo "5. Checking RTPEngine logs..."
echo "-------------------------------------------"
sudo docker compose logs rtpengine --tail 30 | grep -iE "error|failed|timeout|disconnect" | tail -10 || echo "No errors found"
echo ""

echo "6. Checking API server logs for call errors..."
echo "-------------------------------------------"
sudo docker compose logs api-server --tail 50 | grep -iE "call.*error|disconnect|timeout|rtp.*fail" | tail -10 || echo "No call errors found"
echo ""

echo "7. Checking network connectivity..."
echo "-------------------------------------------"
echo "Testing internal network..."
sudo docker compose exec drachtio-sbc ping -c 2 rtpengine > /dev/null 2>&1 && echo "✅ drachtio-sbc can reach rtpengine" || echo "❌ drachtio-sbc cannot reach rtpengine"
sudo docker compose exec drachtio-sbc ping -c 2 api-server > /dev/null 2>&1 && echo "✅ drachtio-sbc can reach api-server" || echo "❌ drachtio-sbc cannot reach api-server"
echo ""

echo "8. Checking RTPEngine configuration..."
echo "-------------------------------------------"
RTPENGINE_CMD=$(sudo docker compose ps rtpengine --format "{{.Command}}" 2>/dev/null || echo "")
echo "RTPEngine command: $RTPENGINE_CMD"
echo ""

echo "=========================================="
echo "Common Causes of Call Disconnects"
echo "=========================================="
echo ""
echo "1. RTPEngine not responding"
echo "   - Check: sudo docker compose logs rtpengine"
echo "   - Restart: sudo docker compose restart rtpengine"
echo ""
echo "2. Network connectivity issues"
echo "   - Check firewall rules"
echo "   - Verify RTP ports (40000-40100) are open"
echo ""
echo "3. SIP signaling problems"
echo "   - Check drachtio-sbc logs for BYE/CANCEL messages"
echo "   - Verify SIP trunk/provider configuration"
echo ""
echo "4. Application errors"
echo "   - Check API server logs"
echo "   - Verify application is handling calls correctly"
echo ""
echo "5. Resource exhaustion"
echo "   - Check: sudo docker stats"
echo "   - Verify sufficient CPU/memory"
echo ""

