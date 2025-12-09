#!/bin/bash
# Final comprehensive check for Exotel integration

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
echo "Final Exotel Integration Check"
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

echo "1. DNS Resolution:"
DNS_IP=$(dig +short $FQDN 2>/dev/null | head -1 || echo "")
if [ "$DNS_IP" = "$HOST_IP" ]; then
  echo "   ✅ $FQDN → $DNS_IP (matches HOST_IP)"
else
  echo "   ❌ $FQDN → $DNS_IP (doesn't match HOST_IP: $HOST_IP)"
fi
echo ""

echo "2. Drachtio Status:"
if $DOCKER_CMD ps | grep -q drachtio-sbc; then
  echo "   ✅ drachtio-sbc is running"
else
  echo "   ❌ drachtio-sbc is NOT running"
fi
echo ""

echo "3. Port Mapping:"
if $DOCKER_CMD port drachtio-sbc 2>/dev/null | grep -q "5060"; then
  echo "   ✅ Port 5060 is mapped"
  $DOCKER_CMD port drachtio-sbc 2>/dev/null | grep 5060
else
  echo "   ❌ Port 5060 not mapped"
fi
echo ""

echo "4. Phone Number Configuration:"
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)
if [ -n "$CARRIER_SID" ]; then
  PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, application_sid FROM phone_numbers WHERE number LIKE '%8064061518%';" 2>/dev/null | grep -v "number" || echo "")
  if [ -n "$PHONE_INFO" ]; then
    echo "   ✅ Phone number configured:"
    echo "$PHONE_INFO"
  else
    echo "   ❌ Phone number not found"
  fi
else
  echo "   ❌ Exotel carrier not found"
fi
echo ""

echo "5. Recent SIP Traffic (last 2 minutes):"
RECENT=$($DOCKER_CMD logs --since 2m drachtio-sbc 2>/dev/null | tail -10 || echo "   No recent traffic")
echo "$RECENT"
echo ""

echo "=========================================="
echo "Exotel Configuration Checklist"
echo "=========================================="
echo ""
echo "In Exotel Dashboard, verify:"
echo ""
echo "1. ✅ Destination URI:"
echo "   Current: sip:graineone.sip.graine.ai:5060;transport=tcp"
echo "   Should be: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "   (Phone number MUST be in the URI)"
echo ""
echo "2. ✅ Phone Number:"
echo "   +918064061518 should be assigned to the trunk"
echo ""
echo "3. ⚠️  IP Whitelisting (optional but recommended):"
echo "   Add: $HOST_IP"
echo ""
echo "=========================================="
echo "Test Steps"
echo "=========================================="
echo ""
echo "1. Update Exotel destination URI to include phone number"
echo "2. Make a test call from Exotel"
echo "3. Monitor logs: sudo docker compose logs -f drachtio-sbc"
echo "4. Look for INVITE message with Request URI containing your phone number"
echo ""

