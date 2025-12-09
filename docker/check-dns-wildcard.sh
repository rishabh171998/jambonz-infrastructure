#!/bin/bash
# Check DNS wildcard configuration

set -e

cd "$(dirname "$0")"

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 | tr -d ' ' || echo "")
fi

if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

FQDN="graineone.sip.graine.ai"

echo "=========================================="
echo "DNS Wildcard Check"
echo "=========================================="
echo ""

echo "1. Testing correct domain: $FQDN"
DNS_IP=$(dig +short $FQDN 2>/dev/null | head -1 || echo "")
if [ -z "$DNS_IP" ]; then
  echo "   ❌ $FQDN does NOT resolve"
else
  echo "   ✅ $FQDN resolves to: $DNS_IP"
  if [ "$DNS_IP" = "$HOST_IP" ]; then
    echo "   ✅ Matches your HOST_IP: $HOST_IP"
  else
    echo "   ⚠️  Does NOT match HOST_IP: $HOST_IP"
  fi
fi
echo ""

echo "2. Testing wildcard: *.sip.graine.ai"
WILDCARD_IP=$(dig +short graineone.sip.graine.ai 2>/dev/null | head -1 || echo "")
if [ -n "$WILDCARD_IP" ]; then
  echo "   ✅ Wildcard is working"
  echo "   Resolves to: $WILDCARD_IP"
else
  echo "   ❌ Wildcard is NOT working"
  echo ""
  echo "   Route53 wildcard format should be:"
  echo "   - Name: *.sip.graine.ai"
  echo "   - Type: A"
  echo "   - Value: $HOST_IP"
fi
echo ""

echo "3. Testing from different locations:"
echo "   (This checks DNS propagation)"
echo ""
echo "   From your Mac:"
echo "   dig $FQDN"
echo ""
echo "   From server:"
echo "   dig $FQDN @8.8.8.8"
echo ""

echo "=========================================="
echo "About Drachtio Entrypoint Changes"
echo "=========================================="
echo ""
echo "The :5060 changes to drachtio-entrypoint.sh are CORRECT and needed."
echo "They don't affect DNS - they just tell drachtio to bind to port 5060."
echo ""
echo "DNS and drachtio are separate:"
echo "  - DNS: Tells Exotel WHERE to send calls (IP address)"
echo "  - Drachtio: Listens for calls on that IP"
echo ""

echo "=========================================="
echo "Fix DNS Issue"
echo "=========================================="
echo ""
echo "If DNS is not resolving:"
echo ""
echo "1. Check Route53:"
echo "   - Go to Route53 → Hosted Zones → graine.ai"
echo "   - Look for: *.sip.graine.ai or graineone.sip.graine.ai"
echo "   - Should point to: $HOST_IP"
echo ""
echo "2. If wildcard exists but not working:"
echo "   - Create explicit A record: graineone.sip.graine.ai → $HOST_IP"
echo ""
echo "3. Wait 5-10 minutes for DNS propagation"
echo ""
echo "4. Test: dig graineone.sip.graine.ai"
echo "   Should return: $HOST_IP"
echo ""

