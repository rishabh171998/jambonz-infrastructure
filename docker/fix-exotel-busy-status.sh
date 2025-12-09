#!/bin/bash
# Fix Exotel "busy" status - diagnose and fix connectivity issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fixing Exotel 'Busy' Status"
echo "=========================================="
echo ""

# Get FQDN and port
FQDN="graineone.sip.graine.ai"
PORT="5060"

echo "Destination URI: sip:$FQDN:$PORT;transport=tcp"
echo ""

# 1. Check DNS
echo "1. Checking DNS resolution..."
DNS_IP=$(dig +short $FQDN 2>/dev/null | head -1 || echo "")
if [ -z "$DNS_IP" ]; then
  echo "   ❌ DNS FAILED: $FQDN does not resolve"
  echo ""
  echo "   FIX: Create DNS A record:"
  echo "   - Name: graineone.sip.graine.ai"
  echo "   - Type: A"
  
  # Get HOST_IP
  if [ -f .env ]; then
    HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
  fi
  if [ -z "$HOST_IP" ]; then
    HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
  fi
  
  if [ -n "$HOST_IP" ]; then
    echo "   - Value: $HOST_IP"
  else
    echo "   - Value: <your-jambonz-public-ip>"
  fi
  echo "   - TTL: 300"
  echo ""
  echo "   This is CRITICAL - Exotel cannot reach you without DNS!"
  exit 1
else
  echo "   ✅ DNS resolves to: $DNS_IP"
fi
echo ""

# 2. Check if port is listening
echo "2. Checking if SBC is listening on TCP $PORT..."
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
  
  if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "   ✅ SBC is listening on TCP $PORT"
  else
    echo "   ❌ SBC is NOT listening on TCP $PORT"
    echo "   Check: docker logs drachtio-sbc"
  fi
else
  echo "   ⚠️  Cannot check (Docker not available)"
fi
echo ""

# 3. Check firewall
echo "3. Firewall Check:"
echo "   ⚠️  CRITICAL: TCP $PORT must be open INBOUND"
echo "   Check AWS Security Group:"
echo "   - Type: Custom TCP"
echo "   - Port: $PORT"
echo "   - Source: 0.0.0.0/0 (or Exotel IPs)"
echo ""

# 4. Check recent SBC logs
echo "4. Checking SBC logs for Exotel connection attempts..."
if [ -n "$DOCKER_CMD" ]; then
  echo "   (Last 30 lines)"
  $DOCKER_CMD logs --tail 30 drachtio-sbc 2>/dev/null | grep -i "exotel\|$FQDN\|$DNS_IP\|invite\|connection" || echo "   No Exotel traffic found"
fi
echo ""

# 5. Summary
echo "=========================================="
echo "Summary & Next Steps"
echo "=========================================="
echo ""

if [ -n "$DNS_IP" ]; then
  echo "✅ DNS: Working ($FQDN → $DNS_IP)"
else
  echo "❌ DNS: NOT WORKING - This is the problem!"
  echo "   Fix DNS first, then test again"
  exit 1
fi

echo ""
echo "Most likely causes of 'busy' status:"
echo ""
echo "1. ❌ Firewall blocking TCP $PORT"
echo "   - Fix: Open TCP $PORT in AWS Security Group"
echo ""
echo "2. ❌ DNS not propagated"
echo "   - Fix: Wait 5-10 minutes after DNS change"
echo "   - Check: dig $FQDN (should show $DNS_IP)"
echo ""
echo "3. ❌ SBC not responding"
echo "   - Check: docker logs drachtio-sbc"
echo "   - Restart: docker restart drachtio-sbc"
echo ""
echo "4. ❌ Port mismatch"
echo "   - Exotel sends to: $FQDN:$PORT"
echo "   - Jambonz listens on: TCP $PORT"
echo "   - Verify they match"
echo ""

echo "Test after fixing:"
echo "  1. Make a test call from Exotel"
echo "  2. Check SBC logs: docker logs -f drachtio-sbc"
echo "  3. Look for SIP INVITE from Exotel"
echo ""

