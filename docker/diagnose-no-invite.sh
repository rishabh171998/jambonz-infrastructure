#!/bin/bash
# Diagnose why no INVITE is coming from Exotel

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
echo "Diagnosing: No INVITE from Exotel"
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

echo "1. DNS Resolution Check:"
DNS_IP=$(dig +short $FQDN 2>/dev/null | head -1 || echo "")
if [ -z "$DNS_IP" ]; then
  echo "   ❌ $FQDN does NOT resolve"
  echo "   This is likely the problem!"
  echo "   Fix: Create DNS A record: $FQDN → $HOST_IP"
else
  echo "   ✅ $FQDN resolves to: $DNS_IP"
  if [ "$DNS_IP" != "$HOST_IP" ]; then
    echo "   ⚠️  WARNING: DNS ($DNS_IP) != HOST_IP ($HOST_IP)"
  fi
fi
echo ""

echo "2. Port Accessibility:"
echo "   Checking if TCP $PORT is listening..."
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":$PORT "; then
  echo "   ✅ TCP $PORT is listening in container"
else
  echo "   ⚠️  TCP $PORT not showing in netstat (might bind on-demand)"
fi
echo ""

echo "3. Recent Connection Attempts:"
echo "   (Last 2 minutes - looking for any Exotel traffic)"
RECENT=$($DOCKER_CMD logs --since 2m drachtio-sbc 2>/dev/null | grep -i "exotel\|182.76\|122.15\|14.194\|61.246\|pstn.in\|connect\|tcp" | tail -10 || echo "   No Exotel traffic found")
if [ -n "$RECENT" ] && [ "$RECENT" != "   No Exotel traffic found" ]; then
  echo "$RECENT"
else
  echo "   ❌ No Exotel connection attempts found"
  echo "   This means Exotel cannot reach Jambonz"
fi
echo ""

echo "4. Check All Recent SIP Traffic:"
echo "   (Last 30 lines)"
$DOCKER_CMD logs --tail 30 drachtio-sbc 2>/dev/null | tail -20
echo ""

echo "=========================================="
echo "Most Likely Causes"
echo "=========================================="
echo ""

if [ -z "$DNS_IP" ]; then
  echo "1. ❌ DNS NOT RESOLVING (MOST LIKELY)"
  echo "   - $FQDN does not resolve"
  echo "   - Exotel cannot find your server"
  echo "   - Fix: Create DNS A record"
  echo ""
fi

echo "2. ❌ Exotel Destination URI Wrong"
echo "   Current: sip:graineone.sip.graine.ai:5060;transport=tcp"
echo "   Should be: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "   (But if DNS doesn't resolve, this won't help)"
echo ""

echo "3. ❌ Firewall Blocking"
echo "   - Check AWS Security Group allows TCP $PORT INBOUND"
echo "   - From: 0.0.0.0/0 (or Exotel IPs)"
echo ""

echo "4. ❌ Exotel Call Not Being Initiated"
echo "   - Check Exotel dashboard: Is call actually being made?"
echo "   - Check Exotel logs for errors"
echo ""

echo "=========================================="
echo "Quick Tests"
echo "=========================================="
echo ""
echo "1. Test DNS:"
echo "   dig $FQDN"
echo "   (Should return: $HOST_IP)"
echo ""
echo "2. Test connectivity from outside:"
echo "   telnet $HOST_IP $PORT"
echo "   (Should connect if firewall allows)"
echo ""
echo "3. Check Exotel dashboard:"
echo "   - Is the call actually being initiated?"
echo "   - Any errors in Exotel call logs?"
echo ""

