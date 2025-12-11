#!/bin/bash
# Fix network issues and start all required services

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fix Network & Start All Services"
echo "=========================================="
echo ""

echo "1. Checking Docker network..."
echo "-------------------------------------------"
NETWORK_EXISTS=$(sudo docker network ls | grep -E "docker_jambonz|jambonz" | head -1 || echo "")
if [ -z "$NETWORK_EXISTS" ]; then
  echo "⚠️  Jambonz network not found, recreating..."
  sudo docker compose down
  sudo docker network prune -f
fi
echo ""

echo "2. Checking which services should be running..."
echo "-------------------------------------------"
echo "Required services:"
echo "  - mysql, redis, jaeger"
echo "  - drachtio-sbc, rtpengine"
echo "  - api-server"
echo "  - sbc-inbound, sbc-outbound, call-router, registrar"
echo "  - drachtio-fs, freeswitch, feature-server"
echo "  - webapp"
echo "  - homer, postgres, heplify-server (optional)"
echo ""

echo "3. Starting all services..."
echo "-------------------------------------------"
echo "This may take a few minutes..."
sudo docker compose up -d
sleep 10
echo ""

echo "4. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps
echo ""

echo "5. Testing network connectivity..."
echo "-------------------------------------------"
echo "Waiting 5 seconds for services to initialize..."
sleep 5

echo ""
echo "Testing drachtio-sbc connectivity:"
sudo docker compose exec drachtio-sbc ping -c 2 rtpengine > /dev/null 2>&1 && echo "✅ drachtio-sbc can reach rtpengine" || echo "❌ drachtio-sbc cannot reach rtpengine"
sudo docker compose exec drachtio-sbc ping -c 2 api-server > /dev/null 2>&1 && echo "✅ drachtio-sbc can reach api-server" || echo "❌ drachtio-sbc cannot reach api-server"
sudo docker compose exec drachtio-sbc ping -c 2 mysql > /dev/null 2>&1 && echo "✅ drachtio-sbc can reach mysql" || echo "❌ drachtio-sbc cannot reach mysql"
echo ""

echo "6. Checking SBC service connections..."
echo "-------------------------------------------"
echo "Checking if sbc-inbound is connecting to drachtio-sbc..."
sleep 3
CONNECTIONS=$(sudo docker compose logs drachtio-sbc --tail 50 | grep -i "client.*connect" | wc -l || echo "0")
if [ "$CONNECTIONS" -gt 0 ]; then
  echo "✅ Found $CONNECTIONS client connection(s) to drachtio-sbc"
  sudo docker compose logs drachtio-sbc --tail 50 | grep -i "client.*connect" | tail -3
else
  echo "⚠️  No client connections to drachtio-sbc yet"
  echo "   Checking sbc-inbound logs..."
  sudo docker compose logs sbc-inbound --tail 10 | grep -iE "connect|error|drachtio" | tail -5 || echo "   sbc-inbound may not be running"
fi
echo ""

echo "7. Checking for errors in critical services..."
echo "-------------------------------------------"
echo "drachtio-sbc:"
sudo docker compose logs drachtio-sbc --tail 10 | grep -i error | tail -3 || echo "  No errors"
echo ""
echo "sbc-inbound:"
sudo docker compose logs sbc-inbound --tail 10 | grep -i error | tail -3 || echo "  No errors (or not running)"
echo ""
echo "api-server:"
sudo docker compose logs api-server --tail 10 | grep -i error | tail -3 || echo "  No errors"
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "If network connectivity is still broken:"
echo "  1. Check Docker network: sudo docker network inspect docker_jambonz"
echo "  2. Restart Docker daemon: sudo systemctl restart docker"
echo "  3. Recreate network: sudo docker compose down && sudo docker compose up -d"
echo ""
echo "If SBC services aren't connecting:"
echo "  1. Check logs: sudo docker compose logs sbc-inbound sbc-outbound"
echo "  2. Verify DRACHTIO_HOST, DRACHTIO_PORT, DRACHTIO_SECRET in docker-compose.yaml"
echo "  3. Restart: sudo docker compose restart sbc-inbound sbc-outbound"
echo ""

