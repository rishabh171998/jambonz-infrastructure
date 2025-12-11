#!/bin/bash
# Fix Homer config and investigate call disconnects

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Homer Config & Investigate Call Disconnects"
echo "=========================================="
echo ""

echo "1. Checking Homer config file..."
echo "-------------------------------------------"
if [ -f "./homer/webapp_config.json" ]; then
  echo "✅ Config file exists"
  ls -lh ./homer/webapp_config.json
else
  echo "❌ Config file not found!"
  echo "   Creating directory..."
  mkdir -p ./homer
  echo "   Please ensure webapp_config.json exists"
fi
echo ""

echo "2. Restarting Homer without read-only mount..."
echo "-------------------------------------------"
sudo docker compose up -d --force-recreate homer
sleep 5
echo "✅ Homer restarted"
echo ""

echo "3. Checking Homer logs..."
echo "-------------------------------------------"
sudo docker compose logs homer --tail 20 | grep -E "error|config|started" || echo "No errors found"
echo ""

echo "4. Checking call disconnect logs..."
echo "-------------------------------------------"
echo "Checking drachtio-sbc logs for disconnects..."
sudo docker compose logs drachtio-sbc --tail 50 | grep -iE "bye|cancel|disconnect|timeout|error" | tail -10 || echo "No disconnect messages found"
echo ""

echo "5. Checking rtpengine status..."
echo "-------------------------------------------"
RTPENGINE_STATUS=$(sudo docker compose ps rtpengine --format "{{.Status}}" 2>/dev/null || echo "")
echo "RTPEngine status: $RTPENGINE_STATUS"
if echo "$RTPENGINE_STATUS" | grep -q "Up"; then
  echo "✅ RTPEngine is running"
else
  echo "⚠️  RTPEngine may have issues"
  echo "   Logs:"
  sudo docker compose logs rtpengine --tail 10
fi
echo ""

echo "6. Checking API server for call errors..."
echo "-------------------------------------------"
sudo docker compose logs api-server --tail 30 | grep -iE "error|disconnect|timeout|failed" | tail -10 || echo "No errors found in recent logs"
echo ""

echo "7. Testing Homer web interface..."
echo "-------------------------------------------"
sleep 3
HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer web interface is accessible (HTTP $HOMER_TEST)"
else
  echo "⚠️  Homer web interface not accessible (HTTP $HOMER_TEST)"
fi
echo ""

echo "=========================================="
echo "Summary & Next Steps"
echo "=========================================="
echo ""
echo "Homer Config:"
echo "  - Removed read-only mount flag"
echo "  - Restart Homer if config still not loading"
echo ""
echo "Call Disconnects:"
echo "  - Check RTPEngine is running and healthy"
echo "  - Check network connectivity"
echo "  - Review drachtio-sbc logs for SIP errors"
echo "  - Check API server logs for application errors"
echo ""
echo "To investigate further:"
echo "  sudo docker compose logs drachtio-sbc --tail 100 | grep -i bye"
echo "  sudo docker compose logs rtpengine --tail 50"
echo "  sudo docker compose logs api-server --tail 100 | grep -i error"
echo ""

