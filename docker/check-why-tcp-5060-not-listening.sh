#!/bin/bash
# Check why TCP 5060 isn't showing as listening (if Twilio works, entrypoint is fine)

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
echo "Why TCP 5060 Not Showing as Listening?"
echo "=========================================="
echo ""

echo "1. Checking if drachtio process is running..."
$DOCKER_CMD exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | head -2
echo ""

echo "2. Checking what drachtio is actually listening on..."
echo "   (All TCP listeners in container):"
$DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep LISTEN || echo "   No TCP listeners found"
echo ""

echo "3. Checking UDP listeners (Twilio uses UDP):"
$DOCKER_CMD exec drachtio-sbc netstat -uln 2>/dev/null | grep 5060 || echo "   UDP 5060 not found"
echo ""

echo "4. Checking drachtio command line arguments:"
$DOCKER_CMD exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | grep -o "drachtio.*" | head -1
echo ""

echo "5. Checking if port 5060 is actually accessible from host:"
if netstat -tln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ Port 5060 is listening on HOST (Docker port mapping works)"
else
  echo "   ❌ Port 5060 is NOT listening on HOST"
  echo "   Check: docker-compose.yaml ports mapping"
fi
echo ""

echo "6. Checking Docker port mappings:"
$DOCKER_CMD port drachtio-sbc 2>/dev/null | grep 5060 || echo "   No 5060 port mapping found"
echo ""

echo "=========================================="
echo "Key Insight"
echo "=========================================="
echo ""
echo "If Twilio works (UDP 5060), then:"
echo "  ✅ Docker port mapping is correct"
echo "  ✅ SBC is running correctly"
echo "  ✅ Entrypoint is fine"
echo ""
echo "The issue might be:"
echo "  1. Drachtio binds to TCP 5060 but netstat doesn't show it"
echo "     (Drachtio might bind on-demand, not pre-bind)"
echo ""
echo "  2. Exotel can't reach TCP 5060 due to:"
echo "     - Firewall blocking TCP 5060 (UDP works, TCP blocked)"
echo "     - DNS not resolving correctly"
echo "     - Exotel trying wrong IP/port"
echo ""
echo "  3. Check if Exotel is actually trying TCP 5060:"
echo "     - Look for TCP connection attempts in logs"
echo "     - Check if Exotel sends to correct destination"
echo ""

echo "7. Checking recent SBC logs for TCP connection attempts:"
echo "   (Looking for 'tcp' or connection attempts)"
$DOCKER_CMD logs --tail 50 drachtio-sbc 2>/dev/null | grep -i "tcp\|connect\|5060" | tail -10 || echo "   No TCP-related logs"
echo ""

echo "=========================================="
echo "Test TCP 5060 from Outside"
echo "=========================================="
echo ""
echo "The real test is: Can Exotel reach TCP 5060?"
echo ""
echo "Test from another machine:"
echo "  telnet <your-ip> 5060"
echo ""
echo "Or check firewall:"
echo "  - AWS Security Group: TCP 5060 INBOUND"
echo "  - Should allow from 0.0.0.0/0 (or Exotel IPs)"
echo ""

