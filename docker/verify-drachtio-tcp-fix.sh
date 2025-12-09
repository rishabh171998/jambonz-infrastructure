#!/bin/bash
# Verify drachtio TCP 5060 fix

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
echo "Verifying Drachtio TCP 5060 Fix"
echo "=========================================="
echo ""

echo "1. Checking if entrypoint was updated correctly..."
if grep -q ":5060" sbc/drachtio-entrypoint.sh; then
  echo "   ✅ Entrypoint has :5060 in contact strings"
  echo "   Current configuration:"
  grep "sip:" sbc/drachtio-entrypoint.sh | grep -v "^#"
else
  echo "   ❌ Entrypoint still missing :5060"
  echo "   File content:"
  cat sbc/drachtio-entrypoint.sh | grep "sip:"
fi
echo ""

echo "2. Checking drachtio process and command line..."
$DOCKER_CMD exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | head -1
echo ""

echo "3. Checking drachtio startup logs (last 30 lines)..."
echo "   (Looking for binding/startup messages)"
$DOCKER_CMD logs --tail 30 drachtio-sbc 2>/dev/null | tail -20
echo ""

echo "4. Checking for any errors in logs..."
$DOCKER_CMD logs --tail 50 drachtio-sbc 2>/dev/null | grep -i "error\|fail\|bind\|5060" | tail -10 || echo "   No obvious errors found"
echo ""

echo "5. Testing if port is accessible (from container)..."
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ TCP 5060 is listening in container"
elif $DOCKER_CMD exec drachtio-sbc netstat -uln 2>/dev/null | grep -q ":5060"; then
  echo "   ⚠️  Only UDP 5060 is listening (TCP not bound yet)"
  echo "   Drachtio might bind TCP on-demand when connection arrives"
else
  echo "   ⚠️  Port 5060 not showing in netstat"
  echo "   This might be normal - drachtio may bind on-demand"
fi
echo ""

echo "6. Checking Docker port mappings..."
$DOCKER_CMD port drachtio-sbc 2>/dev/null | grep 5060 || echo "   (Port mapping check)"
echo ""

echo "=========================================="
echo "Key Point"
echo "=========================================="
echo ""
echo "Drachtio might bind TCP 5060 'on-demand' - meaning it only"
echo "binds when a connection attempt is made, not at startup."
echo ""
echo "This is why netstat doesn't show it until Exotel tries to connect."
echo ""
echo "The real test:"
echo "  1. Make a test call from Exotel"
echo "  2. Check logs: docker logs -f drachtio-sbc"
echo "  3. Look for TCP connection or SIP INVITE"
echo ""
echo "If you see TCP connection in logs when Exotel calls, it's working!"
echo ""

