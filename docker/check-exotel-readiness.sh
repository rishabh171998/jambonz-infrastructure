#!/bin/bash
# Check if Exotel configuration is ready for calls

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
echo "Exotel Configuration Readiness Check"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "✅ Carrier found: $CARRIER_SID"
echo ""

# Check outbound gateway
echo "📋 Outbound Gateway Configuration:"
OUTBOUND=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND outbound = 1;" 2>/dev/null | grep -v "ipv4" || echo "")

if echo "$OUTBOUND" | grep -q "pstn.in"; then
  if echo "$OUTBOUND" | grep -q "5070.*tcp"; then
    echo "✅ Outbound: Correct (FQDN:5070 TCP)"
  else
    echo "❌ Outbound: Wrong port/protocol (should be 5070 TCP)"
  fi
else
  echo "❌ Outbound: No gateway found"
fi
echo "$OUTBOUND"
echo ""

# Check inbound gateways
echo "📋 Inbound Gateway Configuration:"
INBOUND=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, inbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;" 2>/dev/null | grep -v "ipv4" || echo "")

if [ -z "$INBOUND" ]; then
  echo "⚠️  No inbound gateways configured"
  echo "   Inbound calls from Exotel may not work"
else
  UDP_COUNT=$(echo "$INBOUND" | grep -c "5060.*udp" || echo "0")
  TCP_COUNT=$(echo "$INBOUND" | grep -c "5070.*tcp" || echo "0")
  
  if [ "$UDP_COUNT" -gt 0 ]; then
    echo "❌ Found $UDP_COUNT inbound gateway(s) with UDP 5060"
    echo "   Should be TCP 5070 for Exotel"
  fi
  
  if [ "$TCP_COUNT" -gt 0 ]; then
    echo "✅ Found $TCP_COUNT inbound gateway(s) with TCP 5070 (correct)"
  fi
fi
echo "$INBOUND"
echo ""

# Check carrier settings
echo "📋 Carrier Settings:"
CARRIER=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT name, is_active, trunk_type, dtmf_type FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
echo "$CARRIER"
echo ""

# Check phone numbers
echo "📋 Phone Numbers Configured:"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, voip_carrier_sid FROM phone_numbers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null | grep -v "number" || echo "  (none)")
if [ -z "$PHONE_NUMBERS" ] || [ "$PHONE_NUMBERS" = "  (none)" ]; then
  echo "⚠️  No phone numbers configured"
  echo "   Inbound calls won't work without phone numbers"
else
  echo "$PHONE_NUMBERS"
fi
echo ""

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
fi

if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

echo "=========================================="
echo "Readiness Summary"
echo "=========================================="
echo ""

# Outbound check
if echo "$OUTBOUND" | grep -q "5070.*tcp"; then
  echo "✅ Outbound calls: READY"
  echo "   Configuration: TCP 5070"
else
  echo "❌ Outbound calls: NOT READY"
  echo "   Fix: Run ./fix-exotel-simple.sh"
fi

# Inbound check
if [ -z "$INBOUND" ]; then
  echo "❌ Inbound calls: NOT READY"
  echo "   Fix: Configure inbound gateways with TCP 5070"
elif echo "$INBOUND" | grep -q "5070.*tcp"; then
  if [ -n "$PHONE_NUMBERS" ] && [ "$PHONE_NUMBERS" != "  (none)" ]; then
    echo "✅ Inbound calls: READY (if Exotel IP whitelisted)"
  else
    echo "⚠️  Inbound calls: PARTIALLY READY"
    echo "   - Gateways configured ✅"
    echo "   - Phone numbers missing ❌"
  fi
else
  echo "❌ Inbound calls: NOT READY"
  echo "   Fix: Run ./fix-exotel-inbound-tcp.sh"
fi

echo ""
echo "📋 Additional Requirements:"
echo ""
echo "1. Exotel Dashboard:"
echo "   - Whitelist your Jambonz public IP: $HOST_IP"
echo "   - Configure phone numbers to route to your SIP trunk"
echo ""
echo "2. Firewall:"
echo "   - TCP 5070 (SIP signaling) - INBOUND and OUTBOUND"
echo "   - UDP 10000-40000 (RTP media) - INBOUND and OUTBOUND"
echo ""
echo "3. Test:"
echo "   - Outbound: Make a call from Jambonz"
echo "   - Inbound: Call your Exotel number"
echo ""

