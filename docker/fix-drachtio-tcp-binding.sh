#!/bin/bash
# Fix drachtio to actually bind to TCP 5060

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
echo "Fixing Drachtio TCP 5060 Binding"
echo "=========================================="
echo ""

# Check if container is running
if ! $DOCKER_CMD ps | grep -q drachtio-sbc; then
  echo "❌ drachtio-sbc container is not running"
  echo "   Start it: $DOCKER_CMD up -d drachtio-sbc"
  exit 1
fi

echo "1. Checking drachtio process..."
$DOCKER_CMD exec drachtio-sbc ps aux 2>/dev/null | grep drachtio | head -2
echo ""

echo "2. Checking drachtio logs for binding errors..."
$DOCKER_CMD logs --tail 100 drachtio-sbc 2>/dev/null | grep -i "bind\|listen\|5060\|tcp\|error" | tail -20
echo ""

echo "3. Checking current entrypoint configuration..."
cat sbc/drachtio-entrypoint.sh | grep -A 5 "exec drachtio"
echo ""

echo "4. The issue: Drachtio might need explicit SIP port binding"
echo "   Current: --contact with transport=tcp"
echo "   But drachtio might not bind TCP port without explicit --sip-port"
echo ""

echo "=========================================="
echo "Solution: Update drachtio-entrypoint.sh"
echo "=========================================="
echo ""

# Check if we need to add --sip-port
if ! grep -q "sip-port\|5060" sbc/drachtio-entrypoint.sh; then
  echo "Adding explicit SIP port binding..."
  
  # Backup
  cp sbc/drachtio-entrypoint.sh sbc/drachtio-entrypoint.sh.backup
  
  # Update to add explicit port
  sed -i 's/--contact "sip:${LOCAL_IP};transport=tcp"/--contact "sip:${LOCAL_IP}:5060;transport=tcp"/' sbc/drachtio-entrypoint.sh
  sed -i 's/--contact "sip:${LOCAL_IP};transport=udp"/--contact "sip:${LOCAL_IP}:5060;transport=udp"/' sbc/drachtio-entrypoint.sh
  
  echo "✅ Updated entrypoint to explicitly bind port 5060"
  echo ""
  echo "5. Restarting drachtio-sbc..."
  $DOCKER_CMD restart drachtio-sbc
  sleep 5
  echo ""
  
  echo "6. Verifying TCP 5060 is now listening..."
  if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":5060"; then
    echo "   ✅ SUCCESS: TCP 5060 is now listening!"
  else
    echo "   ⚠️  Still not showing in netstat (might bind on-demand)"
    echo "   Check: docker logs drachtio-sbc"
  fi
else
  echo "Entrypoint already has port 5060 configured"
fi

echo ""
echo "=========================================="
echo "Test"
echo "=========================================="
echo ""
echo "1. Check logs: docker logs -f drachtio-sbc"
echo "2. Make test call from Exotel"
echo "3. Look for TCP connection in logs"
echo ""

