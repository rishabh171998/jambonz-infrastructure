#!/bin/bash
# Monitor for Exotel TCP connections and SIP traffic

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  echo "ERROR: Neither 'docker compose' nor 'docker-compose' found"
  exit 1
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Monitoring Exotel TCP Connections"
echo "=========================================="
echo ""
echo "This will monitor drachtio-sbc logs for:"
echo "  - TCP connections from Exotel"
echo "  - SIP INVITEs from Exotel IPs"
echo "  - Any errors"
echo ""
echo "Press Ctrl+C to stop"
echo ""
echo "Now make a test call from Exotel..."
echo ""

# Monitor logs in real-time
$DOCKER_CMD logs -f drachtio-sbc 2>&1 | grep --line-buffered -i "exotel\|pstn.in\|182.76\|122.15\|14.194\|61.246\|tcp\|invite\|5060" || {
  echo ""
  echo "No Exotel traffic detected yet."
  echo ""
  echo "Check:"
  echo "  1. Is Exotel actually sending calls?"
  echo "  2. Is DNS resolving correctly? (graineone.sip.graine.ai)"
  echo "  3. Check firewall allows TCP 5060"
  echo ""
}

