#!/bin/bash
# Script to restart all jambonz services with correct configurations
# This includes all database setup and configuration steps

set -e  # Exit on error

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for prune flag
PRUNE_DOCKER=false
if [ "$1" == "--prune" ] || [ "$1" == "-p" ]; then
  PRUNE_DOCKER=true
fi

echo "=== Restarting all Jambonz services ==="
echo ""

if [ "$PRUNE_DOCKER" = true ]; then
  echo "⚠️  WARNING: This will remove all unused Docker images, containers, and volumes!"
  echo "   This includes:"
  echo "   - All stopped containers"
  echo "   - All unused images"
  echo "   - All unused volumes"
  echo "   - All unused networks"
  echo ""
  read -p "Are you sure you want to continue? (yes/no) " -r
  if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
    echo "Cancelled. Restarting without prune..."
  else
    echo ""
    echo "=== Pruning Docker system ==="
    sudo docker system prune -a --volumes --force
    echo "✓ Docker system pruned"
    echo ""
  fi
fi

echo ""
echo "=== Pulling latest images ==="
sudo docker compose pull

echo ""
echo "=== Stopping all services ==="
sudo docker compose down

echo ""
echo "=== Starting all services ==="
sudo docker compose up -d

echo ""
echo "=== Waiting for MySQL to be healthy ==="
timeout=60
counter=0
while ! sudo docker compose exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent; do
    sleep 2
    counter=$((counter + 2))
    if [ $counter -ge $timeout ]; then
        echo "ERROR: MySQL did not become healthy within $timeout seconds"
        exit 1
    fi
done
echo "MySQL is healthy"

echo ""
echo "=== Setting up database ==="

# Add pad_crypto column to sip_gateways table (if not exists)
echo "Adding pad_crypto column to sip_gateways table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE sip_gateways" 2>/dev/null | grep -q "pad_crypto"; then
    echo "  pad_crypto column already exists, skipping..."
else
    echo "  Adding pad_crypto column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE sip_gateways 
ADD COLUMN pad_crypto BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'P-Asserted-Identity crypto flag';
EOF
    echo "  ✓ pad_crypto column added"
fi

# Add record_all_calls column to accounts table (if not exists)
echo "Adding record_all_calls column to accounts table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "record_all_calls"; then
    echo "  record_all_calls column already exists, skipping..."
else
    echo "  Adding record_all_calls column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN record_all_calls BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'If true, record all calls for this account';
EOF
    echo "  ✓ record_all_calls column added"
fi

# Add record_format column to accounts table (if not exists)
echo "Adding record_format column to accounts table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "record_format"; then
    echo "  record_format column already exists, skipping..."
else
    echo "  Adding record_format column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN record_format VARCHAR(16) NOT NULL DEFAULT 'mp3' 
COMMENT 'Audio format for call recordings (mp3, wav, etc.)';
EOF
    echo "  ✓ record_format column added"
fi

# Add bucket_credential column to accounts table (if not exists)
echo "Adding bucket_credential column to accounts table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "bucket_credential"; then
    echo "  bucket_credential column already exists, skipping..."
else
    echo "  Adding bucket_credential column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN bucket_credential VARCHAR(8192) 
COMMENT 'credential used to authenticate with storage service';
EOF
    echo "  ✓ bucket_credential column added"
fi

# Add enable_debug_log column to accounts table (if not exists)
echo "Adding enable_debug_log column to accounts table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "enable_debug_log"; then
    echo "  enable_debug_log column already exists, skipping..."
else
    echo "  Adding enable_debug_log column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN enable_debug_log BOOLEAN NOT NULL DEFAULT false 
COMMENT 'Enable debug logging for calls in this account';
EOF
    echo "  ✓ enable_debug_log column added"
fi

# Add missing columns to voip_carriers table (if not exists)
echo "Checking voip_carriers table columns..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE voip_carriers" 2>/dev/null | grep -q "^dtmf_type"; then
    echo "  ✓ dtmf_type column already exists"
else
    echo "  Adding dtmf_type column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE voip_carriers 
ADD COLUMN dtmf_type ENUM('rfc2833','tones','info') NOT NULL DEFAULT 'rfc2833' 
COMMENT 'DTMF type for outbound calls: rfc2833 (RFC 2833), tones (in-band), or info (SIP INFO)';
EOF
    echo "  ✓ dtmf_type column added"
fi

if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE voip_carriers" 2>/dev/null | grep -q "^outbound_sip_proxy"; then
    echo "  ✓ outbound_sip_proxy column already exists"
else
    echo "  Adding outbound_sip_proxy column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE voip_carriers 
ADD COLUMN outbound_sip_proxy VARCHAR(255) 
COMMENT 'Optional SIP proxy for outbound calls';
EOF
    echo "  ✓ outbound_sip_proxy column added"
fi

if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE voip_carriers" 2>/dev/null | grep -q "^trunk_type"; then
    echo "  ✓ trunk_type column already exists"
else
    echo "  Adding trunk_type column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE voip_carriers 
ADD COLUMN trunk_type ENUM('static_ip','auth','reg') NOT NULL DEFAULT 'static_ip' 
COMMENT 'Trunk authentication type: static_ip (IP whitelist), auth (SIP auth), or reg (SIP registration)';
EOF
    echo "  ✓ trunk_type column added"
fi

# Create lcr table (if not exists)
echo "Checking lcr table..."
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE lcr" > /dev/null 2>&1; then
    echo "  ✓ lcr table already exists"
else
    echo "  Creating lcr table..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
CREATE TABLE IF NOT EXISTS lcr
(
  lcr_sid CHAR(36) NOT NULL UNIQUE,
  name VARCHAR(64) COMMENT 'User-assigned name for this LCR table',
  is_active BOOLEAN NOT NULL DEFAULT 1,
  default_carrier_set_entry_sid CHAR(36) COMMENT 'default carrier/route to use when no digit match based results are found.',
  service_provider_sid CHAR(36),
  account_sid CHAR(36),
  PRIMARY KEY (lcr_sid)
) COMMENT='An LCR (least cost routing) table that is used by a service provider';
EOF
    echo "  ✓ lcr table created"
    
    # Create indexes for lcr table
    echo "  Creating indexes for lcr table..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
DELIMITER //
CREATE PROCEDURE CreateIndexIfNotExists(IN tableName VARCHAR(255), IN indexName VARCHAR(255), IN indexColumns VARCHAR(255))
BEGIN
    IF NOT EXISTS (SELECT * FROM information_schema.statistics WHERE table_schema = DATABASE() AND table_name = tableName AND index_name = indexName) THEN
        SET @s = CONCAT('CREATE INDEX ', indexName, ' ON ', tableName, ' (', indexColumns, ')');
        PREPARE stmt FROM @s;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END //
DELIMITER ;

CALL CreateIndexIfNotExists('lcr', 'lcr_sid_idx', 'lcr_sid');
CALL CreateIndexIfNotExists('lcr', 'service_provider_sid_idx', 'service_provider_sid');
CALL CreateIndexIfNotExists('lcr', 'account_sid_idx', 'account_sid');

DROP PROCEDURE IF EXISTS CreateIndexIfNotExists;
EOF
    echo "  ✓ lcr indexes created"
    
    # Add foreign key to lcr_routes if missing
    echo "  Checking lcr_routes foreign key..."
    if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT CONSTRAINT_NAME FROM information_schema.TABLE_CONSTRAINTS WHERE CONSTRAINT_TYPE = 'FOREIGN KEY' AND TABLE_NAME = 'lcr_routes' AND REFERENCED_TABLE_NAME = 'lcr';" 2>/dev/null | grep -q "lcr_sid_idxfk"; then
        echo "  ✓ Foreign key lcr_sid_idxfk already exists"
    else
        echo "  Adding foreign key to lcr_routes..."
        sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE lcr_routes ADD CONSTRAINT lcr_sid_idxfk FOREIGN KEY (lcr_sid) REFERENCES lcr (lcr_sid);
EOF
        echo "  ✓ Foreign key added to lcr_routes"
    fi
fi

# Enable CDRs for default account
echo "Enabling CDRs for default account..."
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET disable_cdrs = 0 WHERE account_sid = '9351f46a-678c-43f5-b8a6-d4eb58d131af';
EOF

echo ""
echo "=== Setting up InfluxDB ==="
echo "Waiting for InfluxDB to be ready..."
sleep 5

# Create jambones database in InfluxDB (InfluxDB 1.8 doesn't support IF NOT EXISTS)
echo "Creating jambones database in InfluxDB..."
if sudo docker compose exec -T influxdb influx -execute "SHOW DATABASES" 2>/dev/null | grep -q "jambones"; then
    echo "  jambones database already exists, skipping..."
else
    echo "  Creating jambones database..."
    sudo docker compose exec -T influxdb influx -execute "CREATE DATABASE jambones" 2>/dev/null && echo "  ✓ jambones database created" || echo "  ✗ Failed to create database (may already exist)"
fi

echo ""
echo "=== Waiting for all services to be ready ==="
sleep 10

echo ""
echo "=== Service Status ==="
sudo docker compose ps

echo ""
echo "=== Verifying key services ==="
echo ""
echo "MySQL:"
sudo docker compose exec mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent && echo "✓ MySQL is healthy" || echo "✗ MySQL is not responding"

echo ""
echo "InfluxDB:"
if sudo docker compose exec -T influxdb influx -execute "SHOW DATABASES" 2>/dev/null | grep -q "jambones"; then
    echo "✓ InfluxDB jambones database exists"
else
    echo "✗ InfluxDB database not found - attempting to create..."
    sudo docker compose exec -T influxdb influx -execute "CREATE DATABASE jambones" 2>/dev/null && echo "  ✓ Created jambones database" || echo "  ✗ Failed to create database"
fi

echo ""
echo "Jaeger:"
if curl -s http://localhost:16686 > /dev/null 2>&1; then
    echo "✓ Jaeger UI is accessible at http://${HOST_IP:-localhost}:16686"
else
    echo "✗ Jaeger UI is not accessible (may need a few more seconds to start)"
fi

echo ""
echo "API Server:"
sudo docker compose logs api-server --tail 3 | grep -q "listening" && echo "✓ API Server is running" || echo "✗ API Server may not be ready"

echo ""
echo "sbc-inbound:"
sudo docker compose logs sbc-inbound --tail 3 | grep -q "listening\|connected" && echo "✓ sbc-inbound is running" || echo "✗ sbc-inbound may not be ready"

echo ""
echo "=== Setup Complete ==="
echo ""
echo "✅ All services restarted and configured"
echo ""
echo "Services are available at:"
if [ -f .env ]; then
    HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '\n' || echo "localhost")
else
    HOST_IP="localhost"
fi
echo "  - Webapp: http://${HOST_IP}:3001"
echo "  - API Server: http://${HOST_IP}:3000"
echo "  - Jaeger UI: http://${HOST_IP}:16686"
echo ""
echo "Database migrations applied:"
echo "  ✓ pad_crypto column (sip_gateways)"
echo "  ✓ record_all_calls, record_format, bucket_credential, enable_debug_log (accounts)"
echo "  ✓ lcr table and indexes"
echo ""
echo "Recording WebSocket configured:"
echo "  ✓ JAMBONZ_RECORD_WS_BASE_URL set in feature-server"
echo "  ✓ JAMBONZ_RECORD_WS_USERNAME/PASSWORD configured"
echo ""
echo "Useful commands:"
echo "  - View logs: sudo docker compose logs -f [service-name]"
echo "  - Check status: sudo docker compose ps"
echo "  - Restart with prune: ./restart-all.sh --prune"
echo ""
