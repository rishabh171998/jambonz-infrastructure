#!/bin/bash
# Start all required Jambonz services

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Start All Jambonz Services"
echo "=========================================="
echo ""

echo "1. Checking current service status..."
echo "-------------------------------------------"
RUNNING=$(sudo docker compose ps --format "{{.Service}}" 2>/dev/null | wc -l || echo "0")
echo "Currently running: $RUNNING services"
echo ""

echo "2. Starting all services (this may take a few minutes)..."
echo "-------------------------------------------"
sudo docker compose up -d

echo ""
echo "Waiting 15 seconds for services to initialize..."
sleep 15
echo ""

echo "3. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps
echo ""

echo "4. Testing network connectivity..."
echo "-------------------------------------------"
echo "Testing drachtio-sbc connectivity:"
sudo docker compose exec drachtio-sbc ping -c 2 rtpengine > /dev/null 2>&1 && echo "✅ drachtio-sbc → rtpengine" || echo "❌ drachtio-sbc → rtpengine (FAILED)"
sudo docker compose exec drachtio-sbc ping -c 2 api-server > /dev/null 2>&1 && echo "✅ drachtio-sbc → api-server" || echo "❌ drachtio-sbc → api-server (FAILED)"
sudo docker compose exec drachtio-sbc ping -c 2 mysql > /dev/null 2>&1 && echo "✅ drachtio-sbc → mysql" || echo "❌ drachtio-sbc → mysql (FAILED)"
echo ""

echo "5. Checking SBC service connections to drachtio-sbc..."
echo "-------------------------------------------"
sleep 5
CONNECTIONS=$(sudo docker compose logs drachtio-sbc --tail 100 | grep -i "client.*connect" | wc -l || echo "0")
if [ "$CONNECTIONS" -gt 0 ]; then
  echo "✅ Found $CONNECTIONS client connection(s)"
  sudo docker compose logs drachtio-sbc --tail 100 | grep -i "client.*connect" | tail -5
else
  echo "⚠️  No client connections yet"
  echo "   Checking sbc-inbound status..."
  SBC_INBOUND_STATUS=$(sudo docker compose ps sbc-inbound --format "{{.Status}}" 2>/dev/null || echo "not running")
  echo "   sbc-inbound: $SBC_INBOUND_STATUS"
  if echo "$SBC_INBOUND_STATUS" | grep -q "Up"; then
    echo "   Checking logs..."
    sudo docker compose logs sbc-inbound --tail 10 | grep -iE "connect|error|drachtio" | tail -5 || echo "   No connection messages"
  fi
fi
echo ""

echo "6. Checking for critical errors..."
echo "-------------------------------------------"
ERRORS=0

# Check drachtio-sbc
if sudo docker compose logs drachtio-sbc --tail 20 | grep -qi "error\|fatal\|panic"; then
  echo "⚠️  drachtio-sbc has errors"
  ERRORS=$((ERRORS + 1))
fi

# Check sbc-inbound
if sudo docker compose ps sbc-inbound | grep -q "Up"; then
  if sudo docker compose logs sbc-inbound --tail 20 | grep -qi "error\|fatal\|panic"; then
    echo "⚠️  sbc-inbound has errors"
    ERRORS=$((ERRORS + 1))
  fi
fi

# Check api-server
if sudo docker compose logs api-server --tail 20 | grep -qi "error\|fatal\|panic"; then
  echo "⚠️  api-server has errors"
  ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -eq 0 ]; then
  echo "✅ No critical errors found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Services should now be running."
echo ""
echo "If network connectivity is still broken:"
echo "  1. Check Docker network: sudo docker network inspect docker_jambonz"
echo "  2. Restart Docker: sudo systemctl restart docker"
echo "  3. Recreate network: sudo docker compose down && sudo docker compose up -d"
echo ""
echo "If SBC services aren't connecting:"
echo "  1. Check logs: sudo docker compose logs sbc-inbound sbc-outbound"
echo "  2. Wait a bit longer - connections may take time"
echo "  3. Restart: sudo docker compose restart sbc-inbound sbc-outbound"
echo ""

