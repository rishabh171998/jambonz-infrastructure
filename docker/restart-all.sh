#!/bin/bash
# Script to restart all jambonz services with correct configurations
# This includes all database setup and configuration steps

set -e  # Exit on error

echo "=== Restarting all Jambonz services ==="
cd /opt/jambonz-infrastructure/docker

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
echo "Services are available at:"
echo "  - Webapp: http://\${HOST_IP}:3001"
echo "  - API Server: http://\${HOST_IP}:3000"
echo "  - Jaeger UI: http://\${HOST_IP}:16686"
echo ""
echo "To view logs: sudo docker compose logs -f [service-name]"
echo "To check service status: sudo docker compose ps"
