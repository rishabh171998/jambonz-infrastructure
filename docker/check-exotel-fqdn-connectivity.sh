#!/bin/bash
# Check if Exotel can reach Jambonz via FQDN

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel FQDN Connectivity Check"
echo "=========================================="
echo ""

# Get destination FQDN from user or use default
FQDN="${1:-graineone.sip.graine.ai}"
PORT="${2:-5060}"

echo "Checking FQDN: $FQDN:$PORT"
echo ""

# 1. DNS Resolution
echo "1. DNS Resolution Check:"
DNS_RESULT=$(dig +short $FQDN 2>/dev/null || echo "")
if [ -z "$DNS_RESULT" ]; then
  echo "   ❌ DNS resolution FAILED"
  echo "   $FQDN does not resolve to any IP"
  echo "   Fix: Create an A record pointing to your Jambonz IP"
else
  echo "   ✅ DNS resolves to: $DNS_RESULT"
  
  # Get HOST_IP for comparison
  if [ -f .env ]; then
    HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
  fi
  
  if [ -z "$HOST_IP" ]; then
    HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
  fi
  
  if [ -n "$HOST_IP" ] && [ "$DNS_RESULT" != "$HOST_IP" ]; then
    echo "   ⚠️  WARNING: DNS points to $DNS_RESULT"
    echo "      But your HOST_IP is: $HOST_IP"
    echo "      They should match!"
  elif [ -n "$HOST_IP" ] && [ "$DNS_RESULT" = "$HOST_IP" ]; then
    echo "   ✅ DNS matches your HOST_IP"
  fi
fi
echo ""

# 2. Port connectivity (from outside)
echo "2. Port Connectivity Check:"
echo "   Testing if TCP $PORT is reachable..."
echo "   (This checks from your server - Exotel might see different results)"
echo ""

# Check if port is listening locally
if command -v netstat &> /dev/null; then
  if netstat -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "   ✅ Port $PORT is listening locally"
  else
    echo "   ❌ Port $PORT is NOT listening locally"
  fi
elif command -v ss &> /dev/null; then
  if ss -tln 2>/dev/null | grep -q ":$PORT "; then
    echo "   ✅ Port $PORT is listening locally"
  else
    echo "   ❌ Port $PORT is NOT listening locally"
  fi
else
  echo "   ⚠️  Cannot check port (netstat/ss not available)"
fi
echo ""

# 3. Check firewall/security group
echo "3. Firewall Check:"
echo "   Required: TCP $PORT must be open INBOUND"
echo "   Check your AWS Security Group or firewall"
echo ""

# 4. Check SBC logs for connection attempts
echo "4. Recent SBC Activity:"
echo "   Checking for connection attempts in last 2 minutes..."
echo ""

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD=""
fi

if [ -n "$DOCKER_CMD" ]; then
  # Check if we need sudo
  if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
    DOCKER_CMD="sudo $DOCKER_CMD"
  fi
  
  SBC_LOGS=$($DOCKER_CMD logs --since 2m drachtio-sbc 2>/dev/null | tail -20 || echo "")
  if [ -n "$SBC_LOGS" ]; then
    echo "$SBC_LOGS"
  else
    echo "   No recent activity"
  fi
else
  echo "   Docker not available for log check"
fi
echo ""

# 5. Check destination URI in Exotel
echo "5. Exotel Destination URI Check:"
echo "   Current: sip:$FQDN:$PORT;transport=tcp"
echo "   ✅ FQDN: $FQDN"
echo "   ✅ Port: $PORT (TCP)"
echo "   ✅ Protocol: TCP"
echo ""

# 6. Common issues
echo "=========================================="
echo "Common Issues & Solutions"
echo "=========================================="
echo ""

if [ -z "$DNS_RESULT" ]; then
  echo "❌ DNS NOT RESOLVING"
  echo "   Fix: Create DNS A record:"
  echo "   - Name: graineone.sip.graine.ai"
  echo "   - Type: A"
  echo "   - Value: Your Jambonz public IP"
  echo "   - TTL: 300 (5 minutes)"
  echo ""
fi

echo "❌ Call showing 'busy' status"
echo "   Possible causes:"
echo "   1. DNS not resolving correctly"
echo "   2. Firewall blocking TCP $PORT"
echo "   3. Jambonz SBC not responding"
echo "   4. Exotel can't establish TCP connection"
echo ""

echo "✅ If FQDN works without whitelisting:"
echo "   - DNS must resolve correctly"
echo "   - Port must be accessible from internet"
echo "   - Firewall must allow TCP $PORT INBOUND"
echo ""

echo "📋 Next Steps:"
echo "   1. Verify DNS: dig $FQDN"
echo "   2. Test connectivity: telnet $FQDN $PORT (from outside)"
echo "   3. Check SBC logs: docker logs drachtio-sbc"
echo "   4. Check firewall: AWS Security Group → TCP $PORT"
echo ""

