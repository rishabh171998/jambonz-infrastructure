#!/bin/bash
# Check if Exotel's Request URI format is causing routing issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Exotel Request URI Format Analysis"
echo "=========================================="
echo ""

echo "1. Exotel Request URI Format:"
echo "-------------------------------------------"
echo "Current format:"
echo "  sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo ""
echo "Issues:"
echo "  ⚠️  Port and transport in domain part (non-standard)"
echo "  ⚠️  Should be: sip:8064061518@graineone.sip.graine.ai"
echo ""

echo "2. Checking if Jambonz can extract phone number:"
echo "-------------------------------------------"
echo "Phone number in URI: 8064061518"
echo ""

# Check if phone number exists
PHONE_EXISTS=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT COUNT(*) FROM phone_numbers WHERE number = '8064061518';
" 2>/dev/null || echo "0")

if [ "$PHONE_EXISTS" -gt 0 ]; then
  echo "✅ Phone number '8064061518' exists in database"
else
  echo "❌ Phone number '8064061518' NOT in database"
fi
echo ""

echo "3. Recent routing attempts:"
echo "-------------------------------------------"
ROUTING_LOGS=$(sudo docker compose logs --since 10m sbc-inbound 2>/dev/null | grep -iE "(8064061518|routing|phone|identify)" | tail -15 || echo "")

if [ -z "$ROUTING_LOGS" ]; then
  echo "❌ No routing logs found for 8064061518"
  echo ""
  echo "This means calls aren't reaching sbc-inbound"
  echo "Possible causes:"
  echo "  1. Gateway IP not whitelisted"
  echo "  2. Request URI format causing parsing failure"
  echo "  3. Calls rejected before reaching sbc-inbound"
else
  echo "$ROUTING_LOGS" | sed 's/^sbc-inbound-1  | //'
fi
echo ""

echo "4. Full INVITE from Exotel:"
echo "-------------------------------------------"
FULL_INVITE=$(sudo docker compose logs --since 10m drachtio-sbc 2>/dev/null | grep -A 15 "8064061518.*INVITE" | head -20 || echo "")

if [ -n "$FULL_INVITE" ]; then
  echo "$FULL_INVITE" | sed 's/^drachtio-sbc-1  | //'
  
  # Check source IP
  SOURCE_IP=$(echo "$FULL_INVITE" | grep "recv.*from udp" | tail -1 | grep -oE "\[[0-9.]+\]" | tr -d '[]' || echo "")
  if [ -n "$SOURCE_IP" ]; then
    echo ""
    echo "Source IP: $SOURCE_IP"
  fi
else
  echo "No recent INVITEs found"
fi
echo ""

echo "5. Gateway IP Check:"
echo "-------------------------------------------"
if [ -n "$SOURCE_IP" ]; then
  CARRIER_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)
  
  if [ -n "$CARRIER_SID" ]; then
    GATEWAY_MATCH=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
    SELECT COUNT(*) 
    FROM sip_gateways 
    WHERE voip_carrier_sid = '$CARRIER_SID' 
    AND inbound = 1 
    AND (
      ipv4 = '$SOURCE_IP' 
      OR '$SOURCE_IP' LIKE CONCAT(ipv4, '%')
      OR ipv4 LIKE CONCAT('$SOURCE_IP', '%')
    );
    " 2>/dev/null || echo "0")
    
    if [ "$GATEWAY_MATCH" -gt 0 ]; then
      echo "✅ Source IP $SOURCE_IP matches gateway"
    else
      echo "❌ Source IP $SOURCE_IP does NOT match any gateway!"
      echo ""
      echo "Current Exotel gateways:"
      sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
      SELECT ipv4, netmask, inbound 
      FROM sip_gateways 
      WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
      " 2>/dev/null
    fi
  fi
else
  echo "Could not determine source IP"
fi
echo ""

echo "=========================================="
echo "Potential Issues & Fixes"
echo "=========================================="
echo ""

echo "Issue 1: Request URI Format"
echo "  Current: sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp"
echo "  Problem: Port/transport in domain may cause parsing issues"
echo ""
echo "  Fix: Update Exotel Destination URI to:"
echo "    sip:8064061518@graineone.sip.graine.ai"
echo "    (Remove :5060;transport=tcp from domain)"
echo ""

if [ -n "$SOURCE_IP" ] && [ "$GATEWAY_MATCH" = "0" ]; then
  echo "Issue 2: Gateway IP Not Whitelisted"
  echo "  Source IP: $SOURCE_IP"
  echo "  Problem: IP not in sip_gateways with inbound=1"
  echo ""
  echo "  Fix: Add gateway:"
  echo "    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF"
  echo "    INSERT INTO sip_gateways ("
  echo "      sip_gateway_sid, ipv4, port, protocol, inbound, outbound, is_active, voip_carrier_sid, netmask"
  echo "    ) VALUES ("
  echo "      UUID(), '$SOURCE_IP', 5060, 'udp', 1, 0, 1, '$CARRIER_SID', 32"
  echo "    );"
  echo "    EOF"
  echo ""
fi

if [ "$PHONE_EXISTS" = "0" ]; then
  echo "Issue 3: Phone Number Not in Database"
  echo "  Problem: Phone number '8064061518' not found"
  echo ""
  echo "  Fix: Add in webapp: Phone Numbers → Add → 8064061518"
  echo ""
fi

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Check Exotel Destination URI format"
echo "2. Verify gateway IP whitelisting"
echo "3. Check sbc-inbound logs for routing errors"
echo "4. Test with corrected Destination URI"
echo ""

