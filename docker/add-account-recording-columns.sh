#!/bin/bash
# Quick script to add missing account recording columns

set -e

echo "=== Adding missing account recording columns ==="
cd "$(dirname "$0")"

# Wait for MySQL to be ready
echo "Waiting for MySQL to be ready..."
timeout=30
counter=0
while ! sudo docker compose exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; do
    sleep 2
    counter=$((counter + 2))
    if [ $counter -ge $timeout ]; then
        echo "ERROR: MySQL is not ready"
        exit 1
    fi
done

# Function to add column if it doesn't exist
add_column_if_missing() {
    local column_name=$1
    local sql=$2
    
    if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "$column_name"; then
        echo "✓ $column_name column already exists"
        return 0
    fi
    
    echo "Adding $column_name column..."
    sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
$sql
EOF
    echo "✓ $column_name column added"
}

# Add record_all_calls
add_column_if_missing "record_all_calls" "ALTER TABLE accounts ADD COLUMN record_all_calls BOOLEAN NOT NULL DEFAULT 0 COMMENT 'If true, record all calls for this account';"

# Add record_format
add_column_if_missing "record_format" "ALTER TABLE accounts ADD COLUMN record_format VARCHAR(16) NOT NULL DEFAULT 'mp3' COMMENT 'Audio format for call recordings (mp3, wav, etc.)';"

# Add bucket_credential
add_column_if_missing "bucket_credential" "ALTER TABLE accounts ADD COLUMN bucket_credential VARCHAR(8192) COMMENT 'credential used to authenticate with storage service';"

# Add enable_debug_log
add_column_if_missing "enable_debug_log" "ALTER TABLE accounts ADD COLUMN enable_debug_log BOOLEAN NOT NULL DEFAULT false COMMENT 'Enable debug logging for calls in this account';"

echo ""
echo "✓ All account recording columns added successfully"
echo ""
echo "You can now refresh the webapp and the errors should be resolved."

