#!/bin/bash
# Find Exotel source IP from rejected calls and add to gateways

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
echo "Find and Add Exotel Source IP"
echo "=========================================="
echo ""

# Get Exotel carrier SID
CARRIER_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%' LIMIT 1;" 2>/dev/null)

if [ -z "$CARRIER_SID" ]; then
  echo "❌ No Exotel carrier found!"
  exit 1
fi

echo "Exotel carrier SID: $CARRIER_SID"
echo ""

echo "1. Finding source IP from recent rejected calls:"
echo "-------------------------------------------"
# Look for the source IP in drachtio logs around the time of rejection
# The rejection happens in sbc-inbound, but the source IP comes from drachtio

# Get recent INVITEs with timestamps
RECENT_INVITES=$(sudo docker compose logs --since 2m drachtio-sbc 2>/dev/null | grep "INVITE sip:" | tail -5 || echo "")

if [ -n "$RECENT_INVITES" ]; then
  echo "Recent INVITEs:"
  echo "$RECENT_INVITES" | sed 's/^drachtio-sbc-1  | //'
  echo ""
  
  # Get source IPs from these INVITEs
  SOURCE_IPS=$(sudo docker compose logs --since 2m drachtio-sbc 2>/dev/null | grep -B 2 "INVITE sip:" | grep "recv.*from udp" | grep -oE "\[[0-9.]+\]" | tr -d '[]' | sort -u || echo "")
  
  if [ -n "$SOURCE_IPS" ]; then
    echo "Source IPs found:"
    echo "$SOURCE_IPS"
  else
    echo "Could not extract source IPs from logs"
    echo ""
    echo "Trying alternative method..."
    # Try to get from sbc-inbound logs with source_address
    SOURCE_IPS=$(sudo docker compose logs --since 2m sbc-inbound 2>/dev/null | grep "rejecting call" | grep -oE '"source_address":"[0-9.]+"' | sed 's/.*"\([0-9.]*\)".*/\1/' | sort -u || echo "")
    
    if [ -n "$SOURCE_IPS" ]; then
      echo "Source IPs from sbc-inbound:"
      echo "$SOURCE_IPS"
    else
      echo "❌ Could not find source IPs"
      echo ""
      echo "Make a test call and immediately check:"
      echo "  sudo docker compose logs --since 30s drachtio-sbc | grep 'INVITE' | grep 'recv.*from'"
      exit 1
    fi
  fi
else
  echo "❌ No recent INVITEs found"
  echo ""
  echo "Make a test call first, then run this script again"
  exit 1
fi
echo ""

echo "2. Current Gateway IPs:"
echo "-------------------------------------------"
CURRENT_IPS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT ipv4 
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1;
" 2>/dev/null | sort || echo "")

if [ -n "$CURRENT_IPS" ]; then
  echo "Current gateway IPs:"
  echo "$CURRENT_IPS"
else
  echo "No gateway IPs configured"
fi
echo ""

echo "3. Adding Missing IPs:"
echo "-------------------------------------------"
ADDED=0
for IP in $SOURCE_IPS; do
  # Check if IP already exists
  EXISTS=$(echo "$CURRENT_IPS" | grep -c "^$IP$" || echo "0")
  
  if [ "$EXISTS" -gt 0 ]; then
    echo "  ✅ IP $IP already exists"
  else
    echo "  Adding IP: $IP"
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
      echo "    ✅ Successfully added"
      ADDED=$((ADDED + 1))
    else
      echo "    ❌ Failed to add"
    fi
  fi
done
echo ""

if [ "$ADDED" -gt 0 ]; then
  echo "4. Restarting sbc-inbound:"
  echo "-------------------------------------------"
  $DOCKER_CMD restart sbc-inbound
  echo "✅ sbc-inbound restarted"
  echo ""
  echo "Wait 30 seconds, then make a test call"
else
  echo "4. No new IPs to add"
  echo ""
  echo "If calls are still rejected, the issue might be:"
  echo "  - Phone number not assigned to Exotel carrier"
  echo "  - Request URI format issue"
  echo "  - Different source IP for each call"
fi
echo ""

echo "5. Verify Configuration:"
echo "-------------------------------------------"
FINAL_GATEWAYS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, inbound, is_active
FROM sip_gateways 
WHERE voip_carrier_sid = '$CARRIER_SID' AND inbound = 1
ORDER BY ipv4;
" 2>/dev/null || echo "")

if [ -n "$FINAL_GATEWAYS" ]; then
  echo "$FINAL_GATEWAYS"
fi
echo ""

