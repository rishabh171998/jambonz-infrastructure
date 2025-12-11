#!/bin/bash
# Add clients table to database

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
echo "Adding clients table"
echo "=========================================="
echo ""

# Check if table exists
TABLE_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT COUNT(*) 
FROM information_schema.tables 
WHERE table_schema = 'jambones' 
AND table_name = 'clients';
" 2>/dev/null || echo "0")

if [ "$TABLE_EXISTS" = "1" ]; then
  echo "✅ clients table already exists"
else
  echo "Creating clients table..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones < mysql/add_clients_table.sql
  
  if [ $? -eq 0 ]; then
    echo "✅ clients table created successfully"
  else
    echo "❌ Failed to create clients table"
    exit 1
  fi
fi

echo ""

# Verify table structure
echo "Verifying table structure..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "
DESCRIBE clients;
" 2>/dev/null

echo ""
echo "=========================================="
echo "✅ Clients table ready"
echo "=========================================="
echo ""
echo "You can now create SIP clients for registration."
echo "Run: sudo ./fix-sip-registration-403.sh"
echo ""

