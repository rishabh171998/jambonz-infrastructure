#!/bin/bash
# Quick verification script for drachtio-sbc

echo "=== Verifying drachtio-sbc Setup ==="
echo ""

cd /opt/jambonz-infrastructure/docker

echo "1. Checking service status:"
docker compose ps drachtio-sbc

echo ""
echo "2. Checking drachtio-sbc logs (last 20 lines):"
docker compose logs --tail=20 drachtio-sbc

echo ""
echo "3. Checking for errors:"
ERRORS=$(docker compose logs drachtio-sbc 2>&1 | grep -i "error\|exception\|failed" | tail -5)
if [ -z "$ERRORS" ]; then
  echo "   ✅ No errors found"
else
  echo "   ⚠️  Found errors:"
  echo "$ERRORS"
fi

echo ""
echo "4. Checking if port 5060 is listening:"
if command -v ss &> /dev/null; then
  sudo ss -tulpn | grep ":5060 " || echo "   ⚠️  Port 5060 not found in ss output"
elif command -v netstat &> /dev/null; then
  sudo netstat -tulpn | grep ":5060 " || echo "   ⚠️  Port 5060 not found in netstat output"
else
  echo "   ⚠️  ss/netstat not available"
fi

echo ""
echo "5. Checking for successful startup indicators:"
docker compose logs drachtio-sbc 2>&1 | grep -i "listening\|started\|ready" | tail -3

echo ""
echo "=== Summary ==="
if docker compose logs drachtio-sbc 2>&1 | grep -qi "starting sip stack"; then
  echo "✅ drachtio-sbc appears to be running correctly"
  echo ""
  echo "Next steps:"
  echo "1. Test from Twilio"
  echo "2. Check Twilio Debugger for connection attempts"
  echo "3. Monitor logs: docker compose logs -f drachtio-sbc sbc-inbound"
else
  echo "⚠️  drachtio-sbc may not have started successfully"
  echo "Check the logs above for details"
fi

