#!/bin/bash
# Check Exotel outbound call configuration

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
echo "Exotel Outbound Configuration Check"
echo "=========================================="
echo ""

# Find Exotel carrier
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found"
  exit 1
fi

echo "Found carrier SID: $CARRIER_SID"
echo ""

echo "1. Outbound SIP Gateway:"
echo "-------------------------------------------"
OUTBOUND_GW=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT ipv4, port, protocol, outbound, is_active FROM sip_gateways WHERE voip_carrier_sid = '$CARRIER_SID' AND outbound = 1;" 2>/dev/null | grep -v "ipv4" || echo "")

if [ -z "$OUTBOUND_GW" ]; then
  echo "❌ No outbound gateway configured"
else
  echo "$OUTBOUND_GW" | while IFS= read -r line; do
    if echo "$line" | grep -q "pstn.in.*5070.*tcp"; then
      echo "✅ $line"
    elif echo "$line" | grep -q "pstn.in"; then
      echo "⚠️  $line (should be port 5070, protocol tcp)"
    else
      echo "❌ $line (should be pstn.in4.exotel.com or pstn.in2.exotel.com)"
    fi
  done
fi
echo ""

echo "2. Carrier E.164 Settings:"
echo "-------------------------------------------"
E164=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT e164_leading_plus FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
if [ "$E164" = "1" ]; then
  echo "✅ E.164 leading +: Enabled"
  echo "   Jambonz will send: sip:+918064061518@pstn.in4.exotel.com:5070"
else
  echo "⚠️  E.164 leading +: Disabled"
  echo "   Jambonz will send: sip:918064061518@pstn.in4.exotel.com:5070"
  echo "   (Consider enabling for standard E.164 format)"
fi
echo ""

echo "3. From Domain (Outbound Settings):"
echo "-------------------------------------------"
FROM_DOMAIN=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT register_sip_realm FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
if [ -n "$FROM_DOMAIN" ]; then
  echo "✅ From Domain: $FROM_DOMAIN"
  if echo "$FROM_DOMAIN" | grep -q "exotel.com"; then
    echo "   ✅ Matches Exotel format"
  else
    echo "   ⚠️  Should be: graine1m.pstn.exotel.com (your Exotel trunk domain)"
  fi
else
  echo "❌ From Domain: Not set"
  echo "   Should be: graine1m.pstn.exotel.com"
  echo "   Configure in: Carriers → Exotel → Outbound & Registration → From Domain"
fi
echo ""

echo "4. Tech Prefix:"
echo "-------------------------------------------"
TECH_PREFIX=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT tech_prefix FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
if [ -z "$TECH_PREFIX" ] || [ "$TECH_PREFIX" = "NULL" ]; then
  echo "✅ Tech Prefix: (empty) - Correct for Exotel"
else
  echo "⚠️  Tech Prefix: $TECH_PREFIX"
  echo "   (Only use if Exotel requires a prefix)"
fi
echo ""

echo "5. Trunk Type:"
echo "-------------------------------------------"
TRUNK_TYPE=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT trunk_type FROM voip_carriers WHERE voip_carrier_sid = '$CARRIER_SID';" 2>/dev/null)
if [ "$TRUNK_TYPE" = "static_ip" ]; then
  echo "✅ Trunk Type: static_ip (correct for IP whitelisting)"
else
  echo "⚠️  Trunk Type: $TRUNK_TYPE"
  echo "   (Should be 'static_ip' for Exotel IP whitelisting)"
fi
echo ""

echo "=========================================="
echo "Expected Outbound INVITE Format"
echo "=========================================="
echo ""
echo "When Jambonz makes an outbound call, it will send:"
echo ""
if [ "$E164" = "1" ]; then
  echo "INVITE sip:+918064061518@pstn.in4.exotel.com:5070 SIP/2.0"
else
  echo "INVITE sip:918064061518@pstn.in4.exotel.com:5070 SIP/2.0"
fi
if [ -n "$FROM_DOMAIN" ]; then
  echo "From: <sip:username@${FROM_DOMAIN}>;tag=..."
else
  echo "From: <sip:username@graine1m.pstn.exotel.com>;tag=..."
  echo "⚠️  (From domain not configured - using default)"
fi
echo "To: <sip:+918064061518@pstn.in4.exotel.com:5070>"
echo ""

echo "=========================================="
echo "Exotel Requirements"
echo "=========================================="
echo ""
echo "1. ✅ IP Whitelisting:"
echo "   - Your Jambonz public IP must be whitelisted in Exotel"
echo "   - Same IP used for inbound calls"
echo ""
echo "2. ✅ Request URI:"
echo "   - Format: sip:+918064061518@pstn.in4.exotel.com:5070"
echo "   - Exotel accepts E.164 with or without +"
echo ""
echo "3. ✅ From Domain:"
echo "   - Must match your Exotel trunk domain"
echo "   - Should be: graine1m.pstn.exotel.com"
echo ""
echo "4. ✅ Protocol:"
echo "   - TCP 5070 (recommended)"
echo "   - Or TLS 443 (if configured)"
echo ""

echo "=========================================="
echo "Testing Outbound Calls"
echo "=========================================="
echo ""
echo "1. Monitor outbound INVITEs:"
echo "   sudo docker compose logs -f drachtio-sbc | grep -i 'invite.*pstn.in'"
echo ""
echo "2. Check sbc-outbound logs:"
echo "   sudo docker compose logs -f sbc-outbound"
echo ""
echo "3. Look for:"
echo "   ✅ INVITE sent to Exotel"
echo "   ✅ 100 Trying received"
echo "   ✅ 180 Ringing received"
echo "   ✅ 200 OK received"
echo "   ❌ 403 Forbidden (check From domain)"
echo "   ❌ 404 Not Found (check Request URI format)"
echo ""

