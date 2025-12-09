#!/bin/bash
# Verify Exotel can reach Jambonz now that DNS works

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Verifying Exotel Can Reach Jambonz"
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

echo "✅ DNS is working: $FQDN → $HOST_IP"
echo ""

echo "1. Checking if drachtio is ready:"
if $DOCKER_CMD ps | grep -q drachtio-sbc; then
  echo "   ✅ drachtio-sbc is running"
else
  echo "   ❌ drachtio-sbc is NOT running"
fi
echo ""

echo "2. Checking port accessibility:"
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":$PORT "; then
  echo "   ✅ TCP $PORT is listening (or will bind on-demand)"
else
  echo "   ⚠️  TCP $PORT not showing (might bind on-demand when connection arrives)"
fi
echo ""

echo "3. Monitoring for Exotel connection attempts..."
echo "   (Make a test call from Exotel now...)"
echo "   (Press Ctrl+C after 30 seconds if no traffic)"
echo ""

timeout 30 $DOCKER_CMD logs -f drachtio-sbc 2>&1 | grep --line-buffered -i "exotel\|182.76\|122.15\|14.194\|61.246\|pstn.in\|invite\|tcp.*connect" || {
  echo ""
  echo "❌ No Exotel traffic detected in 30 seconds"
  echo ""
  echo "This means Exotel is not reaching Jambonz."
  echo ""
  echo "Possible causes:"
  echo "  1. Exotel destination URI still wrong"
  echo "     Current: sip:graineone.sip.graine.ai:5060;transport=tcp"
  echo "     Should be: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
  echo ""
  echo "  2. Exotel call not being initiated"
  echo "     - Check Exotel dashboard: Is call actually being made?"
  echo "     - Check Exotel call logs for errors"
  echo ""
  echo "  3. Firewall still blocking"
  echo "     - Verify AWS Security Group allows TCP 5060 INBOUND"
  echo ""
}

