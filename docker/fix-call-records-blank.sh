#!/bin/bash

# Comprehensive fix for blank call records page
# This script addresses multiple potential issues

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Fixing Blank Call Records Page"
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

# Step 1: Add missing lcr table
echo "Step 1: Checking lcr table..."
if ! $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SHOW TABLES LIKE 'lcr'" 2>/dev/null | grep -q "lcr"; then
  echo "  Creating lcr table..."
  ./add-lcr-table.sh
else
  echo "  ✅ lcr table exists"
fi
echo ""

# Step 2: Ensure InfluxDB database exists
echo "Step 2: Checking InfluxDB database..."
if ! $DOCKER_CMD exec -T influxdb influx -execute "SHOW DATABASES" 2>/dev/null | grep -q "jambones"; then
  echo "  Creating jambones database in InfluxDB..."
  $DOCKER_CMD exec -T influxdb influx -execute "CREATE DATABASE jambones" 2>/dev/null && echo "  ✅ Created" || echo "  ⚠️  Failed (may already exist)"
else
  echo "  ✅ jambones database exists"
fi
echo ""

# Step 3: Enable CDRs for all accounts
echo "Step 3: Enabling CDRs for all accounts..."
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET disable_cdrs = 0;
SELECT account_sid, name, disable_cdrs FROM accounts;
EOF
echo "  ✅ CDRs enabled for all accounts"
echo ""

# Step 4: Check API server status
echo "Step 4: Checking API server status..."
if $DOCKER_CMD ps api-server | grep -q "Up"; then
  echo "  ✅ API server is running"
  
  # Check for recent errors
  echo ""
  echo "  Recent API server logs (last 20 lines):"
  $DOCKER_CMD logs api-server --tail 20 2>/dev/null | tail -10 || echo "  Could not get logs"
else
  echo "  ❌ API server is not running"
  echo "  Restarting API server..."
  $DOCKER_CMD restart api-server
  echo "  Waiting for API server to start..."
  sleep 10
fi
echo ""

# Step 5: Check webapp status
echo "Step 5: Checking webapp status..."
if $DOCKER_CMD ps webapp | grep -q "Up"; then
  echo "  ✅ Webapp is running"
else
  echo "  ❌ Webapp is not running"
  echo "  Restarting webapp..."
  $DOCKER_CMD restart webapp
  echo "  Waiting for webapp to start..."
  sleep 10
fi
echo ""

# Step 6: Test API endpoint
echo "Step 6: Testing API endpoint..."
if [ -f .env ]; then
  HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '\n' || echo "localhost")
else
  HOST_IP="localhost"
fi

ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  echo "  Testing: http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25"
  
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls?page=1&count=25" 2>/dev/null || echo "000")
  
  if [ "$HTTP_CODE" = "200" ]; then
    echo "  ✅ API endpoint is accessible (200 OK)"
  elif [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
    echo "  ⚠️  API endpoint requires authentication ($HTTP_CODE)"
    echo "     This is expected - the endpoint exists"
  elif [ "$HTTP_CODE" = "000" ]; then
    echo "  ❌ API endpoint is not accessible (connection failed)"
  else
    echo "  ⚠️  API endpoint returned: $HTTP_CODE"
  fi
else
  echo "  ⚠️  Could not find account SID to test"
fi
echo ""

echo "=========================================="
echo "✅ Fix Complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo ""
echo "1. Clear your browser cache and refresh the page"
echo "2. Open browser developer console (F12) and check for errors"
echo "3. If still blank, check API server logs:"
echo "   sudo docker compose logs api-server --tail 50"
echo ""
echo "4. Test the API endpoint directly:"
echo "   ./test-recent-calls-api.sh"
echo ""
echo "5. If the forEach error persists, the API might be returning:"
echo "   - An error response instead of data"
echo "   - Null/undefined for the data field"
echo "   - A different response structure than expected"
echo ""
echo "   Check API server code to ensure it returns:"
echo "   { data: [], page: 1, total: 0 } for empty results"
echo ""

