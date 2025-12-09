#!/bin/bash
# Quick script to add record_all_calls column to accounts table

set -e

echo "=== Adding record_all_calls column to accounts table ==="
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

# Check if column exists
if sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE accounts" 2>/dev/null | grep -q "record_all_calls"; then
    echo "✓ record_all_calls column already exists"
    exit 0
fi

# Add the column
echo "Adding record_all_calls column..."
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
ALTER TABLE accounts 
ADD COLUMN record_all_calls BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'If true, record all calls for this account';
EOF

echo "✓ record_all_calls column added successfully"
echo ""
echo "You can now refresh the webapp and the error should be resolved."

