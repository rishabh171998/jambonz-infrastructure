#!/bin/bash
# Quick diagnostic script for Twilio connection issues

set -e

echo "=== Jambonz Twilio Connection Diagnostics ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if we're in the right directory
if [ ! -f "docker-compose.yaml" ]; then
    echo -e "${RED}❌ Error: docker-compose.yaml not found${NC}"
    echo "Please run this script from the docker directory:"
    echo "  cd /opt/jambonz-infrastructure/docker"
    echo "  ./diagnose-twilio.sh"
    exit 1
fi

echo "1. HOST_IP Environment Variable:"
if [ -z "$HOST_IP" ]; then
    echo -e "   ${RED}❌ HOST_IP is NOT SET${NC}"
    echo "   Please set it: export HOST_IP=13.203.223.245"
    HOST_IP_CHECK="FAIL"
else
    echo -e "   ${GREEN}✅ HOST_IP=${HOST_IP}${NC}"
    HOST_IP_CHECK="PASS"
fi
echo ""

echo "2. Docker Services Status:"
SERVICES=$(docker compose ps --format json 2>/dev/null || docker-compose ps --format json 2>/dev/null)
if [ -z "$SERVICES" ]; then
    echo -e "   ${RED}❌ Docker Compose not running or services not found${NC}"
    SERVICE_CHECK="FAIL"
else
    echo "   Checking critical services..."
    for service in drachtio-sbc sbc-inbound sbc-outbound; do
        STATUS=$(echo "$SERVICES" | grep -i "$service" | grep -i "running" || echo "")
        if [ -z "$STATUS" ]; then
            echo -e "   ${RED}❌ $service: NOT RUNNING${NC}"
            SERVICE_CHECK="FAIL"
        else
            echo -e "   ${GREEN}✅ $service: Running${NC}"
        fi
    done
fi
echo ""

echo "3. Port 5060 Listening:"
if command -v netstat &> /dev/null; then
    PORT_CHECK=$(sudo netstat -tulpn 2>/dev/null | grep ":5060 " || echo "")
elif command -v ss &> /dev/null; then
    PORT_CHECK=$(sudo ss -tulpn 2>/dev/null | grep ":5060 " || echo "")
else
    PORT_CHECK=""
    echo -e "   ${YELLOW}⚠️  netstat/ss not available, skipping port check${NC}"
fi

if [ -z "$PORT_CHECK" ]; then
    echo -e "   ${RED}❌ Port 5060 not listening${NC}"
    PORT_CHECK_RESULT="FAIL"
else
    echo -e "   ${GREEN}✅ Port 5060 is listening:${NC}"
    echo "$PORT_CHECK" | sed 's/^/      /'
    PORT_CHECK_RESULT="PASS"
fi
echo ""

echo "4. DNS Resolution:"
DNS_RESULT=$(dig +short graineone.sip.graine.ai 2>/dev/null || echo "")
if [ -z "$DNS_RESULT" ]; then
    echo -e "   ${RED}❌ DNS not resolving for graineone.sip.graine.ai${NC}"
    DNS_CHECK="FAIL"
else
    echo -e "   ${GREEN}✅ graineone.sip.graine.ai resolves to: ${DNS_RESULT}${NC}"
    if [ "$DNS_RESULT" = "13.203.223.245" ]; then
        DNS_CHECK="PASS"
    else
        echo -e "   ${YELLOW}⚠️  Expected: 13.203.223.245, Got: ${DNS_RESULT}${NC}"
        DNS_CHECK="WARN"
    fi
fi
echo ""

echo "5. drachtio-sbc Logs (last 10 lines):"
DOCKER_CMD="docker compose"
if ! command -v docker &> /dev/null || ! docker compose version &> /dev/null; then
    DOCKER_CMD="docker-compose"
fi

LOGS=$($DOCKER_CMD logs --tail=10 drachtio-sbc 2>/dev/null || echo "")
if [ -z "$LOGS" ]; then
    echo -e "   ${YELLOW}⚠️  Could not retrieve logs${NC}"
else
    echo "$LOGS" | sed 's/^/   /'
    
    # Check for key indicators
    if echo "$LOGS" | grep -qi "contact.*${HOST_IP:-13.203.223.245}"; then
        echo -e "   ${GREEN}✅ Contact IP looks correct${NC}"
    else
        echo -e "   ${YELLOW}⚠️  Contact IP may not match HOST_IP${NC}"
    fi
    
    if echo "$LOGS" | grep -qi "listening.*5060"; then
        echo -e "   ${GREEN}✅ Listening on port 5060${NC}"
    else
        echo -e "   ${YELLOW}⚠️  May not be listening on port 5060${NC}"
    fi
fi
echo ""

echo "6. Security Group Check:"
echo "   Please verify in AWS Console:"
echo "   - Port 5060 TCP/UDP is open from 0.0.0.0/0 or Twilio IPs"
echo "   - Port 5061 TCP is open (if using TLS)"
echo ""

echo "7. Quick Connectivity Test:"
echo "   Testing if port 5060 is reachable..."
if command -v nc &> /dev/null; then
    if timeout 3 nc -zv ${HOST_IP:-13.203.223.245} 5060 2>&1 | grep -q "succeeded"; then
        echo -e "   ${GREEN}✅ Port 5060 is reachable${NC}"
        CONNECTIVITY_CHECK="PASS"
    else
        echo -e "   ${RED}❌ Port 5060 is NOT reachable${NC}"
        CONNECTIVITY_CHECK="FAIL"
    fi
else
    echo -e "   ${YELLOW}⚠️  nc (netcat) not available, skipping connectivity test${NC}"
    CONNECTIVITY_CHECK="SKIP"
fi
echo ""

echo "=== Summary ==="
echo ""
if [ "$HOST_IP_CHECK" = "PASS" ] && [ "$SERVICE_CHECK" != "FAIL" ] && [ "$PORT_CHECK_RESULT" = "PASS" ] && [ "$DNS_CHECK" = "PASS" ]; then
    echo -e "${GREEN}✅ Basic checks passed. If Twilio still can't connect:${NC}"
    echo "   1. Check Twilio Debugger for detailed error messages"
    echo "   2. Verify SIP realm matches in Jambonz account"
    echo "   3. Check sbc-inbound logs: docker compose logs sbc-inbound"
    echo "   4. Verify Twilio Origination URI format"
else
    echo -e "${RED}❌ Some checks failed. Please fix the issues above.${NC}"
    echo ""
    echo "Common fixes:"
    if [ "$HOST_IP_CHECK" = "FAIL" ]; then
        echo "   - Set HOST_IP: export HOST_IP=13.203.223.245"
        echo "   - Restart: HOST_IP=13.203.223.245 docker compose up -d"
    fi
    if [ "$SERVICE_CHECK" = "FAIL" ]; then
        echo "   - Start services: docker compose up -d"
        echo "   - Check logs: docker compose logs"
    fi
    if [ "$PORT_CHECK_RESULT" = "FAIL" ]; then
        echo "   - Restart drachtio-sbc: docker compose restart drachtio-sbc"
        echo "   - Check logs: docker compose logs drachtio-sbc"
    fi
    if [ "$DNS_CHECK" = "FAIL" ]; then
        echo "   - Verify Route53 A record for graineone.sip.graine.ai"
        echo "   - Wait for DNS propagation (up to 5 minutes)"
    fi
fi
echo ""

