#!/bin/bash
# Fix drachtio-sbc connection issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Drachtio-SBC Connections"
echo "=========================================="
echo ""

echo "1. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps drachtio-sbc sbc-inbound sbc-outbound call-router registrar
echo ""

echo "2. Checking if SBC services are running..."
echo "-------------------------------------------"
SBC_INBOUND=$(sudo docker compose ps sbc-inbound --format "{{.Status}}" 2>/dev/null || echo "not running")
SBC_OUTBOUND=$(sudo docker compose ps sbc-outbound --format "{{.Status}}" 2>/dev/null || echo "not running")
CALL_ROUTER=$(sudo docker compose ps call-router --format "{{.Status}}" 2>/dev/null || echo "not running")
REGISTRAR=$(sudo docker compose ps registrar --format "{{.Status}}" 2>/dev/null || echo "not running")

echo "sbc-inbound: $SBC_INBOUND"
echo "sbc-outbound: $SBC_OUTBOUND"
echo "call-router: $CALL_ROUTER"
echo "registrar: $REGISTRAR"
echo ""

echo "3. Starting SBC services if not running..."
echo "-------------------------------------------"
if echo "$SBC_INBOUND" | grep -q "not running\|Exited"; then
  echo "Starting sbc-inbound..."
  sudo docker compose up -d sbc-inbound
  sleep 2
fi

if echo "$SBC_OUTBOUND" | grep -q "not running\|Exited"; then
  echo "Starting sbc-outbound..."
  sudo docker compose up -d sbc-outbound
  sleep 2
fi

if echo "$CALL_ROUTER" | grep -q "not running\|Exited"; then
  echo "Starting call-router..."
  sudo docker compose up -d call-router
  sleep 2
fi

if echo "$REGISTRAR" | grep -q "not running\|Exited"; then
  echo "Starting registrar..."
  sudo docker compose up -d registrar
  sleep 2
fi
echo ""

echo "4. Checking drachtio-sbc logs for connections..."
echo "-------------------------------------------"
echo "Waiting 5 seconds for services to connect..."
sleep 5
sudo docker compose logs drachtio-sbc --tail 20 | grep -iE "client.*connect|sbc-inbound|sbc-outbound|registrar" || echo "No connection messages found"
echo ""

echo "5. Checking sbc-inbound logs..."
echo "-------------------------------------------"
sudo docker compose logs sbc-inbound --tail 20 | grep -iE "connect|error|drachtio" | tail -10 || echo "No connection messages"
echo ""

echo "6. Checking sbc-outbound logs..."
echo "-------------------------------------------"
sudo docker compose logs sbc-outbound --tail 20 | grep -iE "connect|error|drachtio" | tail -10 || echo "No connection messages"
echo ""

echo "7. Testing drachtio-sbc connectivity..."
echo "-------------------------------------------"
# Check if drachtio-sbc is listening on port 9022
DRACHTIO_9022=$(sudo docker compose exec drachtio-sbc netstat -tlnp 2>/dev/null | grep 9022 || echo "")
if [ -n "$DRACHTIO_9022" ]; then
  echo "✅ drachtio-sbc is listening on port 9022"
else
  echo "⚠️  drachtio-sbc may not be listening on port 9022"
  echo "   Checking drachtio.conf.xml..."
  if [ -f "./sbc/drachtio.conf.xml" ]; then
    grep -E "admin-port|contact" ./sbc/drachtio.conf.xml | head -5
  fi
fi
echo ""

echo "8. Verifying network connectivity..."
echo "-------------------------------------------"
sudo docker compose exec sbc-inbound ping -c 2 drachtio-sbc > /dev/null 2>&1 && echo "✅ sbc-inbound can reach drachtio-sbc" || echo "❌ sbc-inbound cannot reach drachtio-sbc"
sudo docker compose exec sbc-outbound ping -c 2 drachtio-sbc > /dev/null 2>&1 && echo "✅ sbc-outbound can reach drachtio-sbc" || echo "❌ sbc-outbound cannot reach drachtio-sbc"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If services are still not connecting:"
echo "  1. Check drachtio.conf.xml has correct admin-port (should be 9022)"
echo "  2. Verify DRACHTIO_SECRET matches (should be 'cymru')"
echo "  3. Check logs: sudo docker compose logs sbc-inbound sbc-outbound"
echo "  4. Restart drachtio-sbc: sudo docker compose restart drachtio-sbc"
echo ""
echo "To check current connections:"
echo "  sudo docker compose logs drachtio-sbc | grep -i 'client.*connect'"
echo ""

