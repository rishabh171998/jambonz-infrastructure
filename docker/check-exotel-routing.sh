#!/bin/bash
# Check Exotel-specific routing issues

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
echo "Exotel Routing Diagnosis"
echo "=========================================="
echo ""

echo "1. Exotel Carrier Configuration:"
echo "-------------------------------------------"
EXOTEL_CARRIER=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT voip_carrier_sid, name, is_active, application_sid
FROM voip_carriers 
WHERE name LIKE '%Exotel%';
" 2>/dev/null || echo "")

if [ -z "$EXOTEL_CARRIER" ] || echo "$EXOTEL_CARRIER" | grep -q "Empty set"; then
  echo "❌ No Exotel carrier found!"
else
  echo "$EXOTEL_CARRIER"
fi
echo ""

echo "2. Exotel SIP Gateways (Inbound):"
echo "-------------------------------------------"
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -n "$CARRIER_SID" ]; then
  EXOTEL_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
  SELECT ipv4, port, protocol, inbound, outbound, is_active
  FROM sip_gateways 
  WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
  " 2>/dev/null || echo "")
  
  if [ -z "$EXOTEL_GATEWAYS" ] || echo "$EXOTEL_GATEWAYS" | grep -q "Empty set"; then
    echo "❌ No inbound gateways configured for Exotel!"
    echo ""
    echo "Fix: Enable inbound on Exotel SIP gateway"
  else
    echo "$EXOTEL_GATEWAYS"
    echo ""
    
    # Check if Exotel IPs are whitelisted
    EXOTEL_IPS=$(echo "$EXOTEL_GATEWAYS" | grep -v "ipv4" | awk '{print $1}' | grep -v "^$" || echo "")
    echo "Expected source IPs from Exotel:"
    echo "$EXOTEL_IPS"
  fi
else
  echo "Could not find Exotel carrier"
fi
echo ""

echo "3. Recent Exotel INVITEs (8064061518):"
echo "-------------------------------------------"
EXOTEL_INVITES=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep "8064061518" | grep "INVITE" | tail -5 || echo "")

if [ -z "$EXOTEL_INVITES" ]; then
  echo "No recent Exotel INVITEs found"
else
  echo "$EXOTEL_INVITES" | sed 's/^drachtio-sbc-1  | //'
  
  # Get source IP
  SOURCE_IP=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep -B 2 "8064061518.*INVITE" | grep "recv.*from udp" | tail -1 | grep -oE "\[[0-9.]+\]" | tr -d '[]' || echo "")
  if [ -n "$SOURCE_IP" ]; then
    echo ""
    echo "Source IP: $SOURCE_IP"
    echo ""
    
    # Check if this IP matches any gateway
    if echo "$EXOTEL_GATEWAYS" | grep -q "$SOURCE_IP"; then
      echo "✅ Source IP matches Exotel gateway"
    else
      echo "⚠️  Source IP doesn't match configured gateways"
      echo "   This IP might need to be added to Exotel gateways"
    fi
  fi
fi
echo ""

echo "4. sbc-inbound logs for Exotel calls:"
echo "-------------------------------------------"
SBC_EXOTEL=$(sudo docker compose logs --since 10m sbc-inbound 2>/dev/null | grep -iE "(8064061518|exotel|147.135)" | tail -20 || echo "")

if [ -z "$SBC_EXOTEL" ]; then
  echo "❌ No sbc-inbound logs for Exotel calls!"
  echo ""
  echo "This suggests:"
  echo "  - Calls aren't reaching sbc-inbound"
  echo "  - Gateway IP doesn't match (not whitelisted)"
  echo "  - Calls are being rejected before routing"
else
  echo "$SBC_EXOTEL" | sed 's/^sbc-inbound-1  | //'
fi
echo ""

echo "5. Gateway IP Matching:"
echo "-------------------------------------------"
if [ -n "$SOURCE_IP" ] && [ -n "$EXOTEL_GATEWAYS" ]; then
  echo "Exotel call from: $SOURCE_IP"
  echo ""
  echo "Checking if this IP is in sip_gateways..."
  
  IP_MATCH=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
  SELECT COUNT(*) 
  FROM sip_gateways 
  WHERE voip_carrier_sid = '$CARRIER_SID' 
  AND inbound = 1 
  AND ('$SOURCE_IP' LIKE CONCAT(ipv4, '%') OR ipv4 LIKE CONCAT('$SOURCE_IP', '%'));
  " 2>/dev/null || echo "0")
  
  if [ "$IP_MATCH" -gt 0 ]; then
    echo "✅ IP matches gateway configuration"
  else
    echo "❌ IP does NOT match any gateway!"
    echo ""
    echo "Fix: Add Exotel source IP to sip_gateways:"
    echo "  IP: $SOURCE_IP"
    echo "  Port: 5060 (or 5070 for TCP)"
    echo "  Protocol: udp (or tcp)"
    echo "  Inbound: 1"
  fi
else
  echo "Could not determine source IP or gateways"
fi
echo ""

echo "6. Phone Number to Carrier Mapping:"
echo "-------------------------------------------"
PHONE_CARRIER=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT pn.number, pn.voip_carrier_sid, vc.name as carrier_name
FROM phone_numbers pn
LEFT JOIN voip_carriers vc ON pn.voip_carrier_sid = vc.voip_carrier_sid
WHERE pn.number = '8064061518';
" 2>/dev/null || echo "")

if [ -n "$PHONE_CARRIER" ]; then
  echo "$PHONE_CARRIER"
  
  PHONE_CARRIER_SID=$(echo "$PHONE_CARRIER" | grep -v "voip_carrier_sid" | awk '{print $2}' | head -1 || echo "")
  if [ "$PHONE_CARRIER_SID" = "$CARRIER_SID" ]; then
    echo ""
    echo "✅ Phone number is assigned to Exotel carrier"
  else
    echo ""
    echo "⚠️  Phone number carrier doesn't match Exotel carrier SID"
  fi
else
  echo "Could not find phone number carrier mapping"
fi
echo ""

echo "=========================================="
echo "Summary & Fixes"
echo "=========================================="
echo ""

if [ -z "$SBC_EXOTEL" ]; then
  echo "❌ CRITICAL: Exotel calls not reaching sbc-inbound"
  echo ""
  echo "Most likely causes:"
  echo "  1. Exotel source IP not in sip_gateways (inbound=1)"
  echo "  2. Gateway IP/netmask doesn't match Exotel IP"
  echo "  3. Calls being rejected at drachtio level"
  echo ""
  echo "Fix:"
  echo "  1. Find Exotel source IP from logs:"
  echo "     sudo docker compose logs drachtio-sbc | grep '8064061518' | grep 'recv.*from'"
  echo ""
  echo "  2. Add that IP to Exotel sip_gateways with inbound=1"
  echo ""
  echo "  3. Or update existing gateway netmask to include Exotel IP"
fi

if [ -n "$SOURCE_IP" ] && [ "$IP_MATCH" = "0" ]; then
  echo "❌ Source IP $SOURCE_IP not in gateway configuration"
  echo ""
  echo "Quick fix script:"
  echo "  sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF"
  echo "  INSERT INTO sip_gateways ("
  echo "    sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active, voip_carrier_sid, netmask"
  echo "  ) VALUES ("
  echo "    UUID(), '$SOURCE_IP', 5060, 'udp', 1, 0, 1, '$CARRIER_SID', 32"
  echo "  );"
  echo "  EOF"
fi
echo ""

