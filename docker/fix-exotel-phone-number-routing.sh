#!/bin/bash
# Fix Exotel phone number routing - calls being treated as user calls instead of phone number calls

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
echo "Exotel Phone Number Routing Fix"
echo "=========================================="
echo ""

echo "1. Problem Identified:"
echo "-------------------------------------------"
echo "sbc-inbound logs show: 'identifyAccount: incoming user call'"
echo "This means calls are being treated as SIP registration calls"
echo "instead of phone number calls."
echo ""

echo "2. Source IPs from Exotel:"
echo "-------------------------------------------"
SOURCE_IPS=$(sudo docker compose logs --since 30m sbc-inbound 2>/dev/null | grep "identifyAccount: incoming user call" | grep -oE '"source_address":"[0-9.]+"' | sed 's/.*"\([0-9.]*\)".*/\1/' | sort -u || echo "")

if [ -n "$SOURCE_IPS" ]; then
  echo "Exotel source IPs:"
  echo "$SOURCE_IPS"
  echo ""
  
  # Check if these IPs are in gateways
  CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)
  
  if [ -n "$CARRIER_SID" ]; then
    echo "3. Checking Gateway Configuration:"
    echo "-------------------------------------------"
    for IP in $SOURCE_IPS; do
      echo "Checking IP: $IP"
      
      GATEWAY_MATCH=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
      SELECT COUNT(*) 
      FROM sip_gateways 
      WHERE voip_carrier_sid = '$CARRIER_SID' 
      AND inbound = 1 
      AND (
        ipv4 = '$IP' 
        OR '$IP' LIKE CONCAT(ipv4, '%')
        OR ipv4 LIKE CONCAT('$IP', '%')
      );
      " 2>/dev/null || echo "0")
      
      if [ "$GATEWAY_MATCH" -gt 0 ]; then
        echo "  ✅ IP $IP is in gateways"
      else
        echo "  ❌ IP $IP is NOT in gateways - needs to be added"
      fi
    done
  fi
else
  echo "Could not determine source IPs"
fi
echo ""

echo "4. Phone Number Lookup:"
echo "-------------------------------------------"
echo "Exotel sends: 8064061518"
echo ""

PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number, voip_carrier_sid, application_sid
FROM phone_numbers 
WHERE number = '8064061518';
" 2>/dev/null || echo "")

if [ -n "$PHONE_INFO" ] && ! echo "$PHONE_INFO" | grep -q "Empty set"; then
  echo "✅ Phone number found:"
  echo "$PHONE_INFO"
  
  PHONE_CARRIER_SID=$(echo "$PHONE_INFO" | grep -v "voip_carrier_sid" | awk '{print $2}' | head -1 || echo "")
  
  if [ -n "$PHONE_CARRIER_SID" ] && [ "$PHONE_CARRIER_SID" = "$CARRIER_SID" ]; then
    echo ""
    echo "✅ Phone number is assigned to Exotel carrier"
  else
    echo ""
    echo "⚠️  Phone number carrier doesn't match Exotel carrier"
  fi
else
  echo "❌ Phone number not found in database"
fi
echo ""

echo "5. Why Calls Are Treated as User Calls:"
echo "-------------------------------------------"
echo "sbc-inbound uses the Request URI to determine call type:"
echo ""
echo "  - If Request URI matches a phone number → Phone number call"
echo "  - If Request URI matches a SIP realm → User call (registration)"
echo ""
echo "Current Request URI:"
echo "  sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "Issue: The domain 'graineone.sip.graine.ai:5060;transport=tcp' might"
echo "       be matching a SIP realm instead of being recognized as a"
echo "       phone number call."
echo ""

echo "6. Checking SIP Realms:"
echo "-------------------------------------------"
SIP_REALMS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT account_sid, sip_realm 
FROM accounts 
WHERE sip_realm IS NOT NULL AND sip_realm != '';
" 2>/dev/null | grep -i "graine" || echo "")

if [ -n "$SIP_REALMS" ]; then
  echo "Found SIP realms that might match:"
  echo "$SIP_REALMS"
  echo ""
  echo "⚠️  If 'graineone.sip.graine.ai' is a SIP realm, calls will be"
  echo "    treated as user calls instead of phone number calls"
else
  echo "No matching SIP realms found"
fi
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""

echo "The issue is that Exotel's Request URI format is causing"
echo "Jambonz to treat calls as SIP user calls instead of phone number calls."
echo ""

echo "Fix 1: Update Exotel Destination URI"
echo "  Change from:"
echo "    sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "  To:"
echo "    sip:8064061518@15.207.113.122"
echo ""
echo "  This uses your IP instead of FQDN, avoiding SIP realm matching"
echo ""

echo "Fix 2: Add Exotel Source IPs to Gateways"
echo "  If source IPs are not whitelisted, add them:"
echo ""

if [ -n "$SOURCE_IPS" ] && [ -n "$CARRIER_SID" ]; then
  for IP in $SOURCE_IPS; do
    GATEWAY_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
    SELECT COUNT(*) 
    FROM sip_gateways 
    WHERE voip_carrier_sid = '$CARRIER_SID' 
    AND ipv4 = '$IP' 
    AND inbound = 1;
    " 2>/dev/null || echo "0")
    
    if [ "$GATEWAY_EXISTS" = "0" ]; then
      echo "  Add IP $IP:"
      echo "    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF"
      echo "    INSERT INTO sip_gateways ("
      echo "      sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active, voip_carrier_sid, netmask"
      echo "    ) VALUES ("
      echo "      UUID(), '$IP', 5060, 'udp', 1, 0, 1, '$CARRIER_SID', 32"
      echo "    );"
      echo "    EOF"
      echo ""
    fi
  done
fi

echo "Fix 3: Restart sbc-inbound after changes"
echo "  sudo docker compose restart sbc-inbound"
echo ""

