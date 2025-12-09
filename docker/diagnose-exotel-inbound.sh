#!/bin/bash
# Diagnose Exotel vSIP inbound call issues

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
echo "Diagnosing Exotel vSIP Inbound Issues"
echo "=========================================="
echo ""

# Get HOST_IP from .env
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '"' | tr -d "'")
  echo "HOST_IP from .env: $HOST_IP"
else
  echo "⚠️  .env file not found, cannot determine HOST_IP"
  HOST_IP=""
fi

echo ""
echo "=== 1. Checking Carrier Configuration ==="
echo ""

# Check if Exotel carrier exists
EXOTEL_CARRIER=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid, name FROM voip_carriers WHERE name LIKE '%Exotel%' OR name LIKE '%exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$EXOTEL_CARRIER" ]; then
  echo "❌ No Exotel carrier found in database"
  echo "   Please create a carrier named 'Exotel' or 'ExotelMumbai'"
else
  echo "✅ Found carrier: $EXOTEL_CARRIER"
  CARRIER_SID=$(echo "$EXOTEL_CARRIER" | awk '{print $1}')
  
  echo ""
  echo "Carrier details:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null
SELECT 
  voip_carrier_sid,
  name,
  is_active,
  trunk_type,
  requires_register
FROM voip_carriers 
WHERE voip_carrier_sid = '$CARRIER_SID';
EOF

  echo ""
  echo "SIP Gateways:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null
SELECT 
  sip_gateway_sid,
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active,
  pad_crypto
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID';
EOF

  echo ""
  echo "Inbound IP Whitelist:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF 2>/dev/null
SELECT 
  ipv4,
  netmask,
  is_active
FROM account_static_ips 
WHERE account_sid IN (
  SELECT account_sid FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID'
)
OR service_provider_sid IN (
  SELECT service_provider_sid FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID'
);
EOF
fi

echo ""
echo "=== 2. Checking SBC Configuration ==="
echo ""

# Check SBC addresses
echo "SBC Addresses in database:"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, tls_port, wss_port FROM sbc_addresses;" 2>/dev/null || echo "  No SBC addresses found"

echo ""
echo "SBC container status:"
$DOCKER_CMD ps | grep -E "sbc|drachtio" || echo "  No SBC containers found"

echo ""
echo "=== 3. Checking Recent SIP Logs ==="
echo ""

echo "SBC Inbound logs (last 20 lines):"
$DOCKER_CMD logs sbc-inbound --tail 20 2>/dev/null | grep -iE "invite|exotel|pstn|182.76|122.15|14.194|61.246" | tail -10 || echo "  No relevant logs found"

echo ""
echo "SBC Outbound logs (last 20 lines):"
$DOCKER_CMD logs sbc-outbound --tail 20 2>/dev/null | grep -iE "invite|exotel|pstn" | tail -10 || echo "  No relevant logs found"

echo ""
echo "=== 4. Checking Network Configuration ==="
echo ""

if [ -n "$HOST_IP" ]; then
  echo "Your Jambonz public IP: $HOST_IP"
  echo ""
  echo "⚠️  IMPORTANT: This IP must be whitelisted in Exotel dashboard"
  echo "   Go to Exotel dashboard → Trunk Settings → Whitelisted IPs"
  echo "   Add: $HOST_IP"
else
  echo "⚠️  Cannot determine HOST_IP - check .env file"
fi

echo ""
echo "RTP Port Range Configuration:"
if [ -f docker-compose.yaml ]; then
  RTP_PORTS=$(grep -A 2 "rtpengine:" docker-compose.yaml | grep "ports:" | grep -oE "[0-9]+-[0-9]+" | head -1)
  if [ -n "$RTP_PORTS" ]; then
    echo "  RTP ports in docker-compose.yaml: $RTP_PORTS"
    echo "  ⚠️  Exotel requires: 10000-40000"
    echo "  Make sure your range overlaps with Exotel's requirement"
  else
    echo "  ⚠️  Could not find RTP port range in docker-compose.yaml"
  fi
fi

echo ""
echo "=== 5. Checking Firewall/Security Group ==="
echo ""

echo "Required ports for Exotel vSIP:"
echo "  - TCP 5070 (SIP signaling - if using TCP)"
echo "  - TCP 443 (SIP signaling - if using TLS)"
echo "  - UDP 10000-40000 (RTP media)"
echo ""
echo "⚠️  Ensure these ports are open in your AWS Security Group"

echo ""
echo "=== 6. Checking Feature Server Logs ==="
echo ""

echo "Feature server logs (last 30 lines with errors):"
$DOCKER_CMD logs feature-server --tail 100 2>/dev/null | grep -iE "error|fail|exotel|carrier|inbound" | tail -10 || echo "  No errors found"

echo ""
echo "=== 7. Common Issues Checklist ==="
echo ""

echo "□ Is your Jambonz public IP ($HOST_IP) whitelisted in Exotel dashboard?"
echo "□ Is the SIP gateway configured with:"
echo "    - Network address: pstn.in2.exotel.com (not graine1m.pstn.exotel.com)"
echo "    - Port: 5070"
echo "    - Protocol: TCP"
echo "    - Inbound: ✅ Checked"
echo "□ Are inbound IPs whitelisted in Jambonz?"
echo "    - 182.76.143.61 / 32"
echo "    - 122.15.8.184 / 32"
echo "    - 14.194.10.247 / 32"
echo "    - 61.246.82.75 / 32"
echo "□ Is RTP port range configured correctly (10000-40000)?"
echo "□ Are AWS Security Group rules allowing:"
echo "    - TCP 5070 from Exotel IPs"
echo "    - UDP 10000-40000 from Exotel IPs"
echo "□ Is the carrier marked as 'Active'?"
echo "□ Is the SIP gateway marked as 'Active'?"

echo ""
echo "=== 8. Testing SIP Connectivity ==="
echo ""

echo "Testing DNS resolution for Exotel signaling server:"
if command -v nslookup &> /dev/null; then
  nslookup pstn.in2.exotel.com 2>/dev/null | grep -A 2 "Name:" || echo "  DNS resolution failed"
else
  echo "  nslookup not available"
fi

echo ""
echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Verify your IP ($HOST_IP) is whitelisted in Exotel"
echo "2. Check SIP gateway configuration matches recommendations"
echo "3. Verify inbound IP whitelist in Jambonz"
echo "4. Check AWS Security Group allows required ports"
echo "5. Review SBC logs for incoming INVITEs"
echo ""

