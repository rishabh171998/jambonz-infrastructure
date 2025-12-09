#!/bin/bash
# Add missing columns to voip_carriers table (dtmf_type, outbound_sip_proxy, trunk_type)

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
echo "Adding missing columns to voip_carriers"
echo "=========================================="
echo ""

# Function to add column if it doesn't exist
add_column_if_missing() {
  local column_name=$1
  local alter_statement=$2
  
  if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE voip_carriers" 2>/dev/null | grep -q "^${column_name}"; then
    echo "✅ Column '${column_name}' already exists"
    return 0
  fi
  
  echo "Adding ${column_name} column..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "${alter_statement}" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    echo "✅ Successfully added ${column_name} column"
    return 0
  else
    echo "❌ Failed to add ${column_name} column"
    return 1
  fi
}

# Add dtmf_type column
add_column_if_missing "dtmf_type" "ALTER TABLE voip_carriers ADD COLUMN dtmf_type ENUM('rfc2833','tones','info') NOT NULL DEFAULT 'rfc2833' COMMENT 'DTMF type for outbound calls: rfc2833 (RFC 2833), tones (in-band), or info (SIP INFO)';"

# Add outbound_sip_proxy column
add_column_if_missing "outbound_sip_proxy" "ALTER TABLE voip_carriers ADD COLUMN outbound_sip_proxy VARCHAR(255) COMMENT 'Optional SIP proxy for outbound calls';"

# Add trunk_type column
add_column_if_missing "trunk_type" "ALTER TABLE voip_carriers ADD COLUMN trunk_type ENUM('static_ip','auth','reg') NOT NULL DEFAULT 'static_ip' COMMENT 'Trunk authentication type: static_ip (IP whitelist), auth (SIP auth), or reg (SIP registration)';"

echo ""
echo "=========================================="
echo "Migration complete!"
echo "=========================================="
echo ""
echo "Verifying all columns were added..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE voip_carriers" 2>/dev/null | grep -E "dtmf_type|outbound_sip_proxy|trunk_type" || echo "⚠️  Some columns not found in DESCRIBE output"
echo ""
echo "✅ You can now save carriers in the webapp without the 'Unknown column' error."

