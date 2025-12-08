#!/bin/bash
# Quick verification script after restarting with HOST_IP

set -e

echo "=== Verifying Twilio Setup After Restart ==="
echo ""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

cd /opt/jambonz-infrastructure/docker

echo "1. Waiting for services to be ready..."
sleep 5

echo ""
echo "2. Checking service status:"
docker compose ps | grep -E "drachtio-sbc|sbc-inbound|sbc-outbound" || echo "Services still starting..."

echo ""
echo "3. Checking drachtio-sbc logs for HOST_IP usage:"
echo "   Looking for contact and external-ip..."
docker compose logs drachtio-sbc 2>/dev/null | grep -i "contact\|external" | tail -5 || echo "   Logs not available yet"

echo ""
echo "4. Checking if port 5060 is listening:"
if command -v netstat &> /dev/null; then
    sudo netstat -tulpn 2>/dev/null | grep ":5060 " || echo "   Port not listening yet (may need a moment)"
elif command -v ss &> /dev/null; then
    sudo ss -tulpn 2>/dev/null | grep ":5060 " || echo "   Port not listening yet (may need a moment)"
fi

echo ""
echo "5. Testing connectivity to port 5060:"
if timeout 2 nc -zv 13.203.223.245 5060 2>&1 | grep -q "succeeded"; then
    echo -e "   ${GREEN}✅ Port 5060 is reachable${NC}"
else
    echo -e "   ${YELLOW}⚠️  Port 5060 may not be reachable yet (check security group)${NC}"
fi

echo ""
echo "6. Checking DNS resolution:"
DNS_IP=$(dig +short graineone.sip.graine.ai 2>/dev/null || echo "")
if [ "$DNS_IP" = "13.203.223.245" ]; then
    echo -e "   ${GREEN}✅ DNS resolves correctly: graineone.sip.graine.ai -> $DNS_IP${NC}"
else
    echo -e "   ${RED}❌ DNS issue: graineone.sip.graine.ai -> $DNS_IP (expected: 13.203.223.245)${NC}"
fi

echo ""
echo "=== Next Steps ==="
echo "1. Wait for all services to be 'Up' (check: docker compose ps)"
echo "2. Verify drachtio-sbc shows correct IP in logs:"
echo "   docker compose logs drachtio-sbc | grep -i 'contact\|external'"
echo "3. Test from Twilio again"
echo ""

