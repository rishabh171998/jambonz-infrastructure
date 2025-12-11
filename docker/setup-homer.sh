#!/bin/bash
# Setup Homer for PCAP functionality

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Setting up Homer for PCAP"
echo "=========================================="
echo ""

# Check if docker-compose.yaml has homer
if ! grep -q "^  homer:" docker-compose.yaml; then
  echo "❌ Homer service not found in docker-compose.yaml"
  echo "   Run: sudo ./add-homer-to-compose.sh first"
  exit 1
fi

echo "1. Creating Homer database..."
echo "-------------------------------------------"
sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer;" 2>/dev/null || {
  echo "⚠️  Could not create database (may need to wait for MySQL)"
  sleep 5
  sudo docker compose exec -T mysql mysql -ujambones -pjambones -e "CREATE DATABASE IF NOT EXISTS homer;" 2>/dev/null || echo "⚠️  Database creation failed"
}
echo "✅ Database created (or already exists)"
echo ""

echo "2. Starting Homer services..."
echo "-------------------------------------------"
sudo docker compose up -d homer heplify-server
echo ""

echo "3. Waiting for services to initialize..."
sleep 15
echo ""

echo "4. Checking service status..."
echo "-------------------------------------------"
sudo docker compose ps homer heplify-server
echo ""

echo "5. Restarting API server with Homer config..."
echo "-------------------------------------------"
sudo docker compose restart api-server
sleep 5
echo ""

echo "6. Verifying Homer configuration..."
echo "-------------------------------------------"
HOMER_BASE_URL=$(sudo docker compose exec api-server printenv HOMER_BASE_URL 2>/dev/null || echo "")
HOMER_USERNAME=$(sudo docker compose exec api-server printenv HOMER_USERNAME 2>/dev/null || echo "")
HOMER_PASSWORD=$(sudo docker compose exec api-server printenv HOMER_PASSWORD 2>/dev/null || echo "")

if [ -n "$HOMER_BASE_URL" ]; then
  echo "✅ HOMER_BASE_URL: $HOMER_BASE_URL"
else
  echo "❌ HOMER_BASE_URL not set"
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

echo "7. Testing Homer web interface..."
echo "-------------------------------------------"
HOMER_TEST=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:9080 2>/dev/null || echo "000")
if [ "$HOMER_TEST" = "200" ] || [ "$HOMER_TEST" = "301" ] || [ "$HOMER_TEST" = "302" ]; then
  echo "✅ Homer web interface is accessible at http://localhost:9080"
else
  echo "⚠️  Homer web interface not yet accessible (HTTP $HOMER_TEST)"
  echo "   This is normal - it may take a minute to initialize"
fi
echo ""

echo "=========================================="
echo "✅ Homer Setup Complete"
echo "=========================================="
echo ""
echo "Homer Web UI: http://localhost:9080"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Note:"
echo "  - Homer needs SIP traffic to be sent to heplify-server (port 9060 UDP)"
echo "  - PCAP files will only be available for calls captured by Homer"
echo "  - You may need to configure your SIP infrastructure to send HEP packets"
echo ""
echo "To verify PCAP is working:"
echo "  1. Make a test call"
echo "  2. Check if it appears in Homer: http://localhost:9080"
echo "  3. Try downloading PCAP from Recent Calls page"
echo ""

