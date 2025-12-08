#!/bin/bash

# Script to update SBC IP addresses in the database with the actual public IP
# This ensures the webapp shows the correct SIP signaling IPs for carriers to whitelist

set -e

# Get the public IP (try multiple methods)
if [ -z "$HOST_IP" ]; then
  # Try AWS metadata service first
  PUBLIC_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null)
  
  # If AWS metadata didn't work, try external services
  if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
  fi
  
  # Try another external service
  if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 https://ifconfig.me 2>/dev/null)
  fi
  
  # Try one more
  if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "" ]; then
    PUBLIC_IP=$(curl -s --max-time 5 http://icanhazip.com 2>/dev/null)
  fi
else
  PUBLIC_IP="$HOST_IP"
fi

if [ -z "$PUBLIC_IP" ] || [ "$PUBLIC_IP" = "" ]; then
  echo "ERROR: Could not determine public IP address"
  echo "Please set HOST_IP environment variable: export HOST_IP=13.203.223.245"
  echo "Or run: HOST_IP=13.203.223.245 ./update-sbc-ip.sh"
  exit 1
fi

echo "Updating SBC addresses in database with IP: $PUBLIC_IP"

# Database connection details (from docker-compose.yaml)
DB_HOST="${DB_HOST:-mysql}"
DB_PORT="${DB_PORT:-3306}"
DB_USER="${DB_USER:-jambones}"
DB_PASS="${DB_PASS:-jambones}"
DB_NAME="${DB_NAME:-jambones}"

# Update all SBC addresses to use the current public IP
# This updates existing records and creates a new one if none exist
docker-compose exec -T mysql mysql -h127.0.0.1 -u"$DB_USER" -p"$DB_PASS" "$DB_NAME" <<EOF
-- Delete old example/test IPs
DELETE FROM sbc_addresses WHERE ipv4 IN ('52.55.111.178', '3.34.102.122', '127.0.0.1', 'localhost');

-- Update existing SBC addresses to current public IP, or insert if none exist
INSERT INTO sbc_addresses (sbc_address_sid, ipv4, port, service_provider_sid)
VALUES ('f6567ae1-bf97-49af-8931-ca014b689995', '$PUBLIC_IP', 5060, NULL)
ON DUPLICATE KEY UPDATE ipv4 = '$PUBLIC_IP', port = 5060;

-- If you have multiple SBCs or want to add more entries, uncomment and modify:
-- INSERT INTO sbc_addresses (sbc_address_sid, ipv4, port, service_provider_sid)
-- VALUES ('de5ed2f1-bccd-4600-a95e-cef46e9a3a4f', '$PUBLIC_IP', 5060, NULL)
-- ON DUPLICATE KEY UPDATE ipv4 = '$PUBLIC_IP', port = 5060;

SELECT 'SBC addresses updated successfully' AS status;
SELECT sbc_address_sid, ipv4, port FROM sbc_addresses;
EOF

echo ""
echo "✅ SBC IP addresses updated successfully!"
echo "The webapp will now show: $PUBLIC_IP:5060 as the SIP signaling IP"
echo ""
echo "You can verify this in the webapp by:"
echo "1. Go to Carriers → Create/Edit Carrier"
echo "2. Look for 'Have your carriers whitelist our SIP signaling IPs' section"
echo "3. It should show: $PUBLIC_IP:5060"

