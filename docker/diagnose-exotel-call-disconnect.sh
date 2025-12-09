#!/bin/bash
# Diagnose why Exotel calls are disconnecting

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
echo "Exotel Call Disconnect Diagnosis"
echo "=========================================="
echo ""

# Get HOST_IP
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
fi

if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

echo "1. Jambonz Public IP: $HOST_IP"
echo "   ⚠️  CRITICAL: This IP must be whitelisted in Exotel Dashboard"
echo ""

# Check SBC logs for recent Exotel attempts
echo "2. Checking SBC logs for Exotel connection attempts..."
echo "   (Looking for SIP INVITEs from Exotel in last 5 minutes)"
echo ""
$DOCKER_CMD logs --since 5m drachtio-sbc 2>/dev/null | grep -i "exotel\|pstn.in\|182.76\|122.15" | tail -20 || echo "   No Exotel traffic found in logs"
echo ""

# Check if SBC is listening on TCP 5060
echo "3. Checking if SBC is listening on TCP 5060..."
if $DOCKER_CMD exec drachtio-sbc netstat -tln 2>/dev/null | grep -q ":5060"; then
  echo "   ✅ SBC is listening on TCP 5060"
else
  echo "   ❌ SBC is NOT listening on TCP 5060"
fi
echo ""

# Check firewall/security group
echo "4. Firewall Check:"
echo "   Required ports:"
echo "   - TCP 5060 (SIP signaling) - INBOUND"
echo "   - UDP 10000-40000 (RTP media) - INBOUND"
echo "   Check your AWS Security Group or firewall rules"
echo ""

# Check carrier configuration
echo "5. Carrier Configuration:"
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -n "$CARRIER_SID" ]; then
  echo "   Carrier SID: $CARRIER_SID"
  
  # Check inbound gateways
  INBOUND_COUNT=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1 AND protocol = 'tcp' AND port = 5070;" 2>/dev/null)
  
  if [ "$INBOUND_COUNT" -gt 0 ]; then
    echo "   ✅ Inbound gateways configured (TCP 5070)"
  else
    echo "   ❌ Inbound gateways NOT configured correctly"
    echo "      Run: ./fix-exotel-inbound-tcp.sh"
  fi
else
  echo "   ❌ No Exotel carrier found"
fi
echo ""

# Check phone numbers
echo "6. Phone Number Configuration:"
PHONE_NUMBERS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT number, voip_carrier_sid, application_sid FROM phone_numbers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null | grep -v "number" || echo "  (none)")
if [ -n "$PHONE_NUMBERS" ] && [ "$PHONE_NUMBERS" != "  (none)" ]; then
  echo "$PHONE_NUMBERS"
else
  echo "   ❌ No phone numbers configured"
fi
echo ""

# Check sbc-inbound logs
echo "7. Checking sbc-inbound logs for errors..."
echo "   (Last 10 lines)"
echo ""
$DOCKER_CMD logs --tail 10 sbc-inbound 2>/dev/null | grep -i "error\|fail\|reject\|busy" || echo "   No obvious errors"
echo ""

echo "=========================================="
echo "Most Likely Issues"
echo "=========================================="
echo ""
echo "1. ❌ IP NOT WHITELISTED IN EXOTEL"
echo "   - Your Jambonz IP: $HOST_IP"
echo "   - Go to Exotel Dashboard → Trunk → Whitelisted IPs"
echo "   - Add: $HOST_IP"
echo ""
echo "2. ❌ Firewall blocking TCP 5060"
echo "   - Check AWS Security Group"
echo "   - Allow TCP 5060 from 0.0.0.0/0 (or Exotel IPs)"
echo ""
echo "3. ❌ Inbound gateways not configured"
echo "   - Run: ./fix-exotel-inbound-tcp.sh"
echo ""
echo "4. ❌ Destination URI mismatch"
echo "   - Current: sip:graineone.sip.graine.ai:5060;transport=tcp"
echo "   - Should match your Jambonz domain/IP"
echo "   - Verify DNS resolves correctly"
echo ""

echo "=========================================="
echo "Quick Fix Steps"
echo "=========================================="
echo ""
echo "1. Whitelist IP in Exotel:"
echo "   - Dashboard → Trunk 'Test' → Whitelisted IPs"
echo "   - Add: $HOST_IP"
echo ""
echo "2. Verify DNS:"
echo "   - Check: dig graineone.sip.graine.ai"
echo "   - Should resolve to: $HOST_IP"
echo ""
echo "3. Test connectivity:"
echo "   - From Exotel, test: telnet $HOST_IP 5060"
echo "   - Should connect (if firewall allows)"
echo ""

