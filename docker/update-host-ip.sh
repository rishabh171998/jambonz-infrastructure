#!/bin/bash

# Script to update HOST_IP (Elastic IP) and reconfigure all services
# This script:
# 1. Updates HOST_IP in .env file
# 2. Restarts all services with new HOST_IP
# 3. Updates SBC IP addresses in database
# 4. Runs database migrations if needed

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Update HOST_IP and Reconfigure Services"
echo "=========================================="
echo ""

# Get HOST_IP from user or environment variable
if [ -z "$HOST_IP" ]; then
  # Try to auto-detect from AWS metadata
  AUTO_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
  
  if [ -n "$AUTO_IP" ]; then
    echo "Auto-detected public IP: $AUTO_IP"
    read -p "Use this IP? (y/n) or enter new IP: " response
    if [[ "$response" == "y" ]] || [[ "$response" == "Y" ]] || [[ -z "$response" ]]; then
      HOST_IP="$AUTO_IP"
    elif [[ "$response" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      HOST_IP="$response"
    else
      read -p "Enter your new Elastic IP or public IP: " HOST_IP
    fi
  else
    read -p "Enter your new Elastic IP or public IP: " HOST_IP
  fi
fi

# Validate IP format (basic check)
if [[ ! "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: Invalid IP address format: $HOST_IP"
  exit 1
fi

echo ""
echo "Using HOST_IP: $HOST_IP"
echo ""

# Step 1: Update .env file
echo "=========================================="
echo "Step 1: Updating .env file"
echo "=========================================="

ENV_FILE=".env"
TEMP_FILE=".env.tmp"

# Create or update .env file
if [ -f "$ENV_FILE" ]; then
  # Copy existing file, remove old HOST_IP line
  grep -v "^HOST_IP=" "$ENV_FILE" > "$TEMP_FILE" 2>/dev/null || touch "$TEMP_FILE"
else
  touch "$TEMP_FILE"
fi

# Append the new HOST_IP
echo "HOST_IP=$HOST_IP" >> "$TEMP_FILE"

# Move temp file to .env
mv "$TEMP_FILE" "$ENV_FILE"
chmod 644 "$ENV_FILE" 2>/dev/null || true

echo "✅ Updated .env file with HOST_IP=$HOST_IP"
echo ""

# Step 2: Export HOST_IP for docker compose
export HOST_IP="$HOST_IP"

# Step 3: Restart services with new HOST_IP
echo "=========================================="
echo "Step 2: Restarting services with new HOST_IP"
echo "=========================================="

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
  echo "Using sudo for Docker commands..."
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "Stopping all services..."
$DOCKER_CMD down

echo ""
echo "Starting services with HOST_IP=$HOST_IP..."
$DOCKER_CMD up -d

echo ""
echo "Waiting for MySQL to be healthy..."
timeout=60
counter=0
while ! $DOCKER_CMD exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; do
    sleep 2
    counter=$((counter + 2))
    if [ $counter -ge $timeout ]; then
        echo "ERROR: MySQL did not become healthy within $timeout seconds"
        exit 1
    fi
done
echo "✅ MySQL is healthy"
echo ""

# Step 4: Update SBC IP addresses in database
echo "=========================================="
echo "Step 3: Updating SBC IP addresses in database"
echo "=========================================="

DB_USER="${DB_USER:-jambones}"
DB_PASS="${DB_PASS:-jambones}"
DB_NAME="${DB_NAME:-jambones}"

$DOCKER_CMD exec -T mysql mysql -h127.0.0.1 -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Delete old example/test IPs
DELETE FROM sbc_addresses WHERE ipv4 IN ('52.55.111.178', '3.34.102.122', '127.0.0.1', 'localhost');

-- Update existing SBC addresses to current public IP, or insert if none exist
INSERT INTO sbc_addresses (sbc_address_sid, ipv4, port, service_provider_sid)
VALUES ('f6567ae1-bf97-49af-8931-ca014b689995', '$HOST_IP', 5060, NULL)
ON DUPLICATE KEY UPDATE ipv4 = '$HOST_IP', port = 5060;

SELECT 'SBC addresses updated successfully' AS status;
SELECT sbc_address_sid, ipv4, port FROM sbc_addresses;
EOF

echo "✅ SBC IP addresses updated in database"
echo ""

# Step 5: Run database migrations (if needed)
echo "=========================================="
echo "Step 4: Running database migrations"
echo "=========================================="

# Add pad_crypto column to sip_gateways table (if not exists)
echo "Checking pad_crypto column..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE sip_gateways" 2>/dev/null | grep -q "pad_crypto"; then
    echo "  ✓ pad_crypto column already exists"
else
    echo "  Adding pad_crypto column..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE sip_gateways 
ADD COLUMN pad_crypto BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'P-Asserted-Identity crypto flag';
EOF
    echo "  ✓ pad_crypto column added"
fi

# Add record_all_calls column to accounts table (if not exists)
echo "Checking record_all_calls column..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "record_all_calls"; then
    echo "  ✓ record_all_calls column already exists"
else
    echo "  Adding record_all_calls column..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN record_all_calls BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'If true, record all calls for this account';
EOF
    echo "  ✓ record_all_calls column added"
fi

# Add record_format column to accounts table (if not exists)
echo "Checking record_format column..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "record_format"; then
    echo "  ✓ record_format column already exists"
else
    echo "  Adding record_format column..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN record_format VARCHAR(16) NOT NULL DEFAULT 'mp3' 
COMMENT 'Audio format for call recordings (mp3, wav, etc.)';
EOF
    echo "  ✓ record_format column added"
fi

# Add bucket_credential column to accounts table (if not exists)
echo "Checking bucket_credential column..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "bucket_credential"; then
    echo "  ✓ bucket_credential column already exists"
else
    echo "  Adding bucket_credential column..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN bucket_credential VARCHAR(8192) 
COMMENT 'credential used to authenticate with storage service';
EOF
    echo "  ✓ bucket_credential column added"
fi

# Add enable_debug_log column to accounts table (if not exists)
echo "Checking enable_debug_log column..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "enable_debug_log"; then
    echo "  ✓ enable_debug_log column already exists"
else
    echo "  Adding enable_debug_log column..."
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN enable_debug_log BOOLEAN NOT NULL DEFAULT false 
COMMENT 'Enable debug logging for calls in this account';
EOF
    echo "  ✓ enable_debug_log column added"
fi

echo ""
echo "✅ Database migrations complete"
echo ""

# Step 6: Verify services
echo "=========================================="
echo "Step 5: Verifying services"
echo "=========================================="

echo "Waiting for services to be ready..."
sleep 10

echo ""
echo "Service Status:"
$DOCKER_CMD ps

echo ""
echo "=========================================="
echo "✅ Update Complete!"
echo "=========================================="
echo ""
echo "HOST_IP has been updated to: $HOST_IP"
echo ""
echo "Services are available at:"
echo "  - Webapp: http://$HOST_IP:3001"
echo "  - API Server: http://$HOST_IP:3000"
echo "  - SIP Signaling: $HOST_IP:5060"
echo ""
echo "SBC IP addresses in database have been updated."
echo "Carriers should whitelist: $HOST_IP:5060"
echo ""
echo "To verify in webapp:"
echo "  1. Go to Carriers → Create/Edit Carrier"
echo "  2. Look for 'Have your carriers whitelist our SIP signaling IPs'"
echo "  3. It should show: $HOST_IP:5060"
echo ""

