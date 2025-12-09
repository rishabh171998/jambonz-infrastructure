#!/bin/bash
# Fix "DID has not been provisioned" error for Exotel calls

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
echo "Fix Exotel DID Provisioning Error"
echo "=========================================="
echo ""
echo "Error: 'rejecting call from carrier because DID has not been provisioned'"
echo ""
echo "This means Jambonz isn't recognizing the call as coming from Exotel carrier"
echo ""

# Get Exotel carrier SID
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found!"
  exit 1
fi

echo "Found Exotel carrier SID: $CARRIER_SID"
echo ""

# Get phone number info
PHONE_NUMBER="8064061518"
echo "1. Phone Number Configuration:"
echo "-------------------------------------------"
PHONE_INFO=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT number, voip_carrier_sid, application_sid
FROM phone_numbers 
WHERE number = '$PHONE_NUMBER';
" 2>/dev/null || echo "")

if [ -z "$PHONE_INFO" ] || echo "$PHONE_INFO" | grep -q "Empty set"; then
  echo "❌ Phone number '$PHONE_NUMBER' not found in database!"
  echo ""
  echo "Fix: Add phone number in webapp: Phone Numbers → Add → $PHONE_NUMBER"
  exit 1
else
  echo "$PHONE_INFO"
  
  PHONE_CARRIER_SID=$(echo "$PHONE_INFO" | grep -v "voip_carrier_sid" | awk '{print $2}' | head -1 || echo "")
  
  if [ "$PHONE_CARRIER_SID" = "$CARRIER_SID" ]; then
    echo ""
    echo "✅ Phone number is assigned to Exotel carrier"
  else
    echo ""
    echo "❌ Phone number carrier mismatch!"
    echo "   Phone number carrier: $PHONE_CARRIER_SID"
    echo "   Exotel carrier: $CARRIER_SID"
    echo ""
    echo "Fix: Update phone number to use Exotel carrier"
  fi
fi
echo ""

echo "2. Exotel Gateway IPs (Inbound):"
echo "-------------------------------------------"
GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, outbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
" 2>/dev/null || echo "")

if [ -z "$GATEWAYS" ] || echo "$GATEWAYS" | grep -q "Empty set"; then
  echo "❌ No inbound gateways configured for Exotel!"
  echo ""
  echo "This is the problem - Exotel source IPs need to be whitelisted"
else
  echo "$GATEWAYS"
fi
echo ""

echo "3. Exotel Source IPs (from logs):"
echo "-------------------------------------------"
SOURCE_IPS=$(sudo docker compose logs --since 30m sbc-inbound 2>/dev/null | grep "rejecting call from carrier" | grep -oE '"source_address":"[0-9.]+"' | sed 's/.*"\([0-9.]*\)".*/\1/' | sort -u || echo "")

if [ -z "$SOURCE_IPS" ]; then
  # Try to get from drachtio logs
  SOURCE_IPS=$(sudo docker compose logs --since 30m drachtio-sbc 2>/dev/null | grep "8064061518.*INVITE" | grep "recv.*from udp" | grep -oE "\[[0-9.]+\]" | tr -d '[]' | sort -u || echo "")
fi

if [ -n "$SOURCE_IPS" ]; then
  echo "Exotel source IPs:"
  echo "$SOURCE_IPS"
  echo ""
  
  echo "4. Checking if source IPs match gateways:"
  echo "-------------------------------------------"
  for IP in $SOURCE_IPS; do
    MATCH=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
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
    
    if [ "$MATCH" -gt 0 ]; then
      echo "  ✅ IP $IP matches gateway"
    else
      echo "  ❌ IP $IP does NOT match any gateway - NEEDS TO BE ADDED"
    fi
  done
else
  echo "Could not determine source IPs from logs"
  echo "Make a test call and check again"
fi
echo ""

echo "=========================================="
echo "Fix: Add Exotel Source IPs to Gateways"
echo "=========================================="
echo ""

if [ -n "$SOURCE_IPS" ]; then
  echo "Adding missing gateway IPs..."
  echo ""
  
  for IP in $SOURCE_IPS; do
    MATCH=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
    SELECT COUNT(*) 
    FROM sip_gateways 
    WHERE voip_carrier_sid = '$CARRIER_SID' 
    AND inbound = 1 
    AND ipv4 = '$IP';
    " 2>/dev/null || echo "0")
    
    if [ "$MATCH" -eq 0 ]; then
      echo "Adding IP: $IP"
      $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO sip_gateways (
  sip_gateway_sid,
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active,
  voip_carrier_sid,
  netmask
) VALUES (
  UUID(),
  '$IP',
  5060,
  'udp',
  1,
  0,
  1,
  '$CARRIER_SID',
  32
);
EOF
      if [ $? -eq 0 ]; then
        echo "  ✅ Added $IP"
      else
        echo "  ❌ Failed to add $IP"
      fi
    else
      echo "  ✅ IP $IP already exists"
    fi
  done
else
  echo "Cannot determine source IPs. Please:"
  echo "  1. Make a test call from Exotel"
  echo "  2. Run: sudo docker compose logs --since 5m sbc-inbound | grep 'rejecting call'"
  echo "  3. Note the source_address IP"
  echo "  4. Add it manually to sip_gateways"
fi
echo ""

echo "5. Verify Configuration:"
echo "-------------------------------------------"
FINAL_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, outbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
" 2>/dev/null || echo "")

if [ -n "$FINAL_GATEWAYS" ]; then
  echo "$FINAL_GATEWAYS"
  echo ""
  echo "✅ Gateways configured"
else
  echo "❌ No gateways found"
fi
echo ""

echo "6. Restart sbc-inbound:"
echo "-------------------------------------------"
echo "Restarting sbc-inbound to apply changes..."
$DOCKER_CMD restart sbc-inbound
echo "✅ sbc-inbound restarted"
echo ""

echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Wait 30 seconds for sbc-inbound to restart"
echo "2. Make a test call from Exotel"
echo "3. Check logs:"
echo "   sudo docker compose logs -f sbc-inbound | grep '$PHONE_NUMBER'"
echo ""
echo "You should see:"
echo "  ✅ 'inbound call accepted for routing' (instead of 'rejecting call')"
echo "  ✅ Call routing to application"
echo ""

