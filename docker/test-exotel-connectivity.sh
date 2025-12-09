#!/bin/bash
# Test if Exotel can reach Jambonz on TCP 5060

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel Connectivity Test"
echo "=========================================="
echo ""

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
fi

if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

FQDN="graineone.sip.graine.ai"
PORT="5060"

echo "1. DNS Resolution Test:"
DNS_IP=$(dig +short $FQDN 2>/dev/null | head -1 || echo "")
if [ -z "$DNS_IP" ]; then
  echo "   ❌ $FQDN does not resolve"
  echo "   Fix: Create DNS A record pointing to $HOST_IP"
else
  echo "   ✅ $FQDN resolves to: $DNS_IP"
  if [ "$DNS_IP" != "$HOST_IP" ]; then
    echo "   ⚠️  WARNING: DNS IP ($DNS_IP) != HOST_IP ($HOST_IP)"
  fi
fi
echo ""

echo "2. Port Accessibility Test:"
echo "   Testing TCP $PORT from container..."
if timeout 2 bash -c "echo > /dev/tcp/$HOST_IP/$PORT" 2>/dev/null; then
  echo "   ✅ TCP $PORT is accessible from container"
else
  echo "   ❌ TCP $PORT is NOT accessible from container"
fi
echo ""

echo "3. Docker Port Mapping:"
# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD=""
fi

if [ -n "$DOCKER_CMD" ]; then
  if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
    DOCKER_CMD="sudo $DOCKER_CMD"
  fi
  
  echo "   Checking port mappings..."
  $DOCKER_CMD port drachtio-sbc 2>/dev/null | grep 5060 || echo "   (check manually)"
fi
echo ""

echo "4. Current Configuration Summary:"
echo "   - Jambonz IP: $HOST_IP"
echo "   - FQDN: $FQDN"
echo "   - DNS resolves to: ${DNS_IP:-NOT RESOLVED}"
echo "   - Port: $PORT (TCP)"
echo "   - Exotel Destination URI: sip:$FQDN:$PORT;transport=tcp"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. If DNS doesn't resolve:"
echo "   - Create A record: $FQDN → $HOST_IP"
echo "   - Wait 5-10 minutes for propagation"
echo ""
echo "2. Test from outside (another machine):"
echo "   telnet $HOST_IP $PORT"
echo "   (Should connect if firewall allows)"
echo ""
echo "3. Make test call from Exotel and monitor:"
echo "   ./monitor-exotel-tcp-connections.sh"
echo ""

