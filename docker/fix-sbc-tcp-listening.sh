#!/bin/bash
# Fix SBC to listen on TCP 5060 for Exotel

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
echo "Fixing SBC TCP 5060 Listening"
echo "=========================================="
echo ""

# Check current status
echo "1. Checking current SBC status..."
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ SBC is already listening on TCP 5060"
  echo "   The issue might be elsewhere (firewall, DNS, etc.)"
  exit 0
else
  echo "   ❌ SBC is NOT listening on TCP 5060"
fi
echo ""

# Check drachtio process
echo "2. Checking drachtio process..."
$DOCKER_CMD exec drachtio-sbc ps aux 2>/dev/null | grep drachtio || echo "   Drachtio process not found"
echo ""

# Check drachtio logs for errors
echo "3. Checking drachtio logs for TCP binding errors..."
$DOCKER_CMD logs --tail 50 drachtio-sbc 2>/dev/null | grep -i "tcp\|5060\|bind\|listen\|error" | tail -10 || echo "   No relevant errors found"
echo ""

# Restart SBC to ensure TCP binding
echo "4. Restarting SBC to ensure TCP binding..."
$DOCKER_CMD restart drachtio-sbc
echo "   Waiting 5 seconds for SBC to start..."
sleep 5
echo ""

# Check again
echo "5. Verifying TCP 5060 is now listening..."
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ SUCCESS: SBC is now listening on TCP 5060"
else
  echo "   ❌ Still not listening on TCP 5060"
  echo ""
  echo "   Checking what ports ARE listening:"
  $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep LISTEN || echo "   No TCP listeners found"
  echo ""
  echo "   This might indicate:"
  echo "   - Drachtio configuration issue"
  echo "   - Port binding problem"
  echo "   - Check: docker logs drachtio-sbc"
fi
echo ""

# Check UDP too
echo "6. Checking UDP 5060..."
if $DOCKER_CMD exec drachtio-sbc netstat -uln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ UDP 5060 is listening"
else
  echo "   ⚠️  UDP 5060 is NOT listening"
fi
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Verify firewall allows TCP 5060 INBOUND"
echo "2. Test from outside: telnet <your-ip> 5060"
echo "3. Make a test call from Exotel"
echo "4. Check logs: docker logs -f drachtio-sbc"
echo ""

