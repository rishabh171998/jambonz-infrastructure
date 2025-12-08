#!/bin/bash
# Script to check CDR status and InfluxDB connectivity

echo "=== Checking Account CDR Settings ==="
sudo docker compose exec mysql mysql -ujambones -pjambones jambones -e "SELECT account_sid, name, disable_cdrs FROM accounts;"

echo ""
echo "=== Checking InfluxDB Connectivity ==="
sudo docker compose exec influxdb influx -execute "SHOW DATABASES"

echo ""
echo "=== Checking if call records exist in InfluxDB ==="
sudo docker compose exec influxdb influx -execute "SHOW MEASUREMENTS" -database jambones 2>/dev/null || echo "Database 'jambones' may not exist yet"

