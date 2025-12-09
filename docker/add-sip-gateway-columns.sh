#!/bin/bash
# Add missing columns to sip_gateways table (protocol, send_options_ping, use_sips_scheme, pad_crypto)

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
echo "Adding missing columns to sip_gateways"
echo "=========================================="
echo ""

# Function to add column if it doesn't exist
add_column_if_missing() {
  local column_name=$1
  local alter_statement=$2
  
  if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE sip_gateways" 2>/dev/null | grep -q "^${column_name}"; then
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

# Add protocol column
add_column_if_missing "protocol" "ALTER TABLE sip_gateways ADD COLUMN protocol ENUM('udp','tcp','tls', 'tls/srtp') DEFAULT 'udp' COMMENT 'Outbound call protocol';"

# Add send_options_ping column
add_column_if_missing "send_options_ping" "ALTER TABLE sip_gateways ADD COLUMN send_options_ping BOOLEAN NOT NULL DEFAULT 0;"

# Add use_sips_scheme column
add_column_if_missing "use_sips_scheme" "ALTER TABLE sip_gateways ADD COLUMN use_sips_scheme BOOLEAN NOT NULL DEFAULT 0;"

# Add pad_crypto column
add_column_if_missing "pad_crypto" "ALTER TABLE sip_gateways ADD COLUMN pad_crypto BOOLEAN NOT NULL DEFAULT 0;"

echo ""
echo "=========================================="
echo "Migration complete!"
echo "=========================================="
echo ""
echo "Verifying all columns were added..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE sip_gateways" 2>/dev/null | grep -E "protocol|send_options_ping|use_sips_scheme|pad_crypto" || echo "⚠️  Some columns not found in DESCRIBE output"
echo ""
echo "✅ You can now save carriers with protocol settings in the webapp."

