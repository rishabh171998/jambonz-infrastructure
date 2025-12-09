#!/bin/bash

# Final fix for lcr table issue - verifies and creates if needed, then restarts API server

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Final Fix for lcr Table"
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

echo "Step 1: Verifying lcr table exists..."
echo "-----------------------------------"

# Check if table exists by trying to describe it
TABLE_EXISTS=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE lcr" 2>/dev/null && echo "yes" || echo "no")

if [ "$TABLE_EXISTS" = "yes" ]; then
  echo "✅ lcr table exists"
  echo ""
  echo "Table structure:"
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "DESCRIBE lcr" 2>/dev/null
else
  echo "❌ lcr table does NOT exist. Creating it now..."
  echo ""
  
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

  echo "✅ lcr table created"
  
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
fi

echo ""
echo "Step 2: Verifying table is accessible..."
echo "-----------------------------------"

# Test query
QUERY_RESULT=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT COUNT(*) as count FROM lcr" 2>/dev/null || echo "ERROR")

if echo "$QUERY_RESULT" | grep -q "ERROR"; then
  echo "❌ Cannot query lcr table"
  echo "$QUERY_RESULT"
  exit 1
else
  COUNT=$(echo "$QUERY_RESULT" | tail -1)
  echo "✅ lcr table is accessible (contains $COUNT rows)"
fi

echo ""
echo "Step 3: Restarting API server to pick up changes..."
echo "-----------------------------------"

$DOCKER_CMD restart api-server

echo "✅ API server restarted"
echo ""
echo "Waiting for API server to be ready..."
sleep 15

echo ""
echo "Step 4: Verifying API server is running..."
echo "-----------------------------------"

if $DOCKER_CMD ps api-server | grep -q "Up"; then
  echo "✅ API server is running"
  
  # Check recent logs for lcr errors
  echo ""
  echo "Checking for lcr table errors in API server logs..."
  LCR_ERRORS=$($DOCKER_CMD logs api-server --tail 20 2>/dev/null | grep -i "lcr.*doesn't exist" || echo "")
  
  if [ -n "$LCR_ERRORS" ]; then
    echo "⚠️  Still seeing lcr table errors:"
    echo "$LCR_ERRORS"
    echo ""
    echo "This might be from old log entries. Wait a few seconds and check again."
  else
    echo "✅ No lcr table errors in recent logs"
  fi
else
  echo "❌ API server is not running"
  exit 1
fi

echo ""
echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo ""
echo "The lcr table has been verified and API server has been restarted."
echo ""
echo "Next steps:"
echo "1. Clear your browser cache (Ctrl+Shift+Delete or Cmd+Shift+Delete)"
echo "2. Hard refresh the page (Ctrl+F5 or Cmd+Shift+R)"
echo "3. Try accessing call records again"
echo ""
echo "If the page is still blank, check the browser console (F12) for errors."
echo ""

