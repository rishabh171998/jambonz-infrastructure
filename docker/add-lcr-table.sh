#!/bin/bash

# Script to add missing lcr table to the database
# This fixes the "Table 'jambones.lcr' doesn't exist" error

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Adding missing lcr table"
echo "=========================================="
echo ""

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

# Check if MySQL is healthy
echo "Checking MySQL status..."
if ! $DOCKER_CMD exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; then
  echo "ERROR: MySQL is not healthy. Please wait for MySQL to start."
  exit 1
fi

echo "✅ MySQL is healthy"
echo ""

# Check if lcr table already exists
echo "Checking if lcr table exists..."
if $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SHOW TABLES LIKE 'lcr'" 2>/dev/null | grep -q "lcr"; then
  echo "✅ lcr table already exists"
  echo ""
  echo "Table structure:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE lcr" 2>/dev/null
  exit 0
fi

echo "⚠️  lcr table does NOT exist. Creating it now..."
echo ""

# Create the lcr table
echo "Creating lcr table..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
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

if [ $? -eq 0 ]; then
  echo "✅ lcr table created successfully"
else
  echo "❌ Failed to create lcr table"
  exit 1
fi

# Create indexes (check if they exist first since MySQL doesn't support IF NOT EXISTS)
echo ""
echo "Creating indexes..."

# Check and create lcr_sid_idx
INDEX_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = 'jambones' AND table_name = 'lcr' AND index_name = 'lcr_sid_idx'" 2>/dev/null || echo "0")
if [ "$INDEX_EXISTS" = "0" ]; then
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "CREATE INDEX lcr_sid_idx ON lcr (lcr_sid)" 2>/dev/null && echo "  ✓ Created lcr_sid_idx" || echo "  ⚠️  Failed to create lcr_sid_idx"
else
  echo "  ✓ lcr_sid_idx already exists"
fi

# Check and create service_provider_sid_idx
INDEX_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = 'jambones' AND table_name = 'lcr' AND index_name = 'service_provider_sid_idx'" 2>/dev/null || echo "0")
if [ "$INDEX_EXISTS" = "0" ]; then
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "CREATE INDEX service_provider_sid_idx ON lcr (service_provider_sid)" 2>/dev/null && echo "  ✓ Created service_provider_sid_idx" || echo "  ⚠️  Failed to create service_provider_sid_idx"
else
  echo "  ✓ service_provider_sid_idx already exists"
fi

# Check and create account_sid_idx
INDEX_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT COUNT(*) FROM information_schema.statistics WHERE table_schema = 'jambones' AND table_name = 'lcr' AND index_name = 'account_sid_idx'" 2>/dev/null || echo "0")
if [ "$INDEX_EXISTS" = "0" ]; then
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "CREATE INDEX account_sid_idx ON lcr (account_sid)" 2>/dev/null && echo "  ✓ Created account_sid_idx" || echo "  ⚠️  Failed to create account_sid_idx"
else
  echo "  ✓ account_sid_idx already exists"
fi

echo "✅ Indexes created/verified"
echo ""

# Try to add foreign key (may fail if lcr_carrier_set_entry table is empty, which is OK)
echo "Adding foreign key constraint..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
SET FOREIGN_KEY_CHECKS=0;
ALTER TABLE lcr 
ADD CONSTRAINT default_carrier_set_entry_sid_idxfk 
FOREIGN KEY (default_carrier_set_entry_sid) 
REFERENCES lcr_carrier_set_entry (lcr_carrier_set_entry_sid);
SET FOREIGN_KEY_CHECKS=1;
EOF

if [ $? -eq 0 ]; then
  echo "✅ Foreign key constraint added"
else
  echo "⚠️  Foreign key constraint may have failed (this is OK if lcr_carrier_set_entry table is empty)"
fi

echo ""
echo "=========================================="
echo "✅ lcr table setup complete!"
echo "=========================================="
echo ""
echo "The call records page should now work."
echo "Please refresh your browser and try accessing call records again."
echo ""

