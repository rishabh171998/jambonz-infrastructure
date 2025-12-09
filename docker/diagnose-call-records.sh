#!/bin/bash

# Script to diagnose call records blank page issue

set -e

cd "$(dirname "$0")"

echo "=========================================="
echo "Diagnosing Call Records Blank Page Issue"
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

echo "1. Checking Account CDR Settings..."
echo "-----------------------------------"
$DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -e "SELECT account_sid, name, disable_cdrs FROM accounts;" 2>/dev/null || echo "ERROR: Could not query accounts"
echo ""

echo "2. Checking InfluxDB Status..."
echo "-----------------------------------"
if $DOCKER_CMD exec -T influxdb influx -execute "SHOW DATABASES" 2>/dev/null | grep -q "jambones"; then
  echo "✅ InfluxDB 'jambones' database exists"
  
  echo ""
  echo "Checking for call records in InfluxDB..."
  MEASUREMENTS=$($DOCKER_CMD exec -T influxdb influx -execute "SHOW MEASUREMENTS" -database jambones 2>/dev/null || echo "")
  if [ -n "$MEASUREMENTS" ]; then
    echo "Measurements found:"
    echo "$MEASUREMENTS"
  else
    echo "⚠️  No measurements found in InfluxDB (no call records yet)"
  fi
else
  echo "❌ InfluxDB 'jambones' database does NOT exist"
  echo "   Creating it now..."
  $DOCKER_CMD exec -T influxdb influx -execute "CREATE DATABASE jambones" 2>/dev/null && echo "   ✅ Created jambones database" || echo "   ❌ Failed to create database"
fi
echo ""

echo "3. Checking API Server Status..."
echo "-----------------------------------"
API_STATUS=$($DOCKER_CMD logs api-server --tail 20 2>/dev/null | grep -i "error\|listening\|started" | tail -5 || echo "")
if [ -n "$API_STATUS" ]; then
  echo "Recent API server logs:"
  echo "$API_STATUS"
else
  echo "⚠️  Could not get API server logs"
fi
echo ""

echo "4. Checking Webapp Status..."
echo "-----------------------------------"
WEBAPP_STATUS=$($DOCKER_CMD logs webapp --tail 20 2>/dev/null | grep -i "error\|listening\|started" | tail -5 || echo "")
if [ -n "$WEBAPP_STATUS" ]; then
  echo "Recent webapp logs:"
  echo "$WEBAPP_STATUS"
else
  echo "⚠️  Could not get webapp logs"
fi
echo ""

echo "5. Testing API Endpoint..."
echo "-----------------------------------"
# Get first account SID
ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")

if [ -n "$ACCOUNT_SID" ]; then
  echo "Testing Recent Calls API for account: $ACCOUNT_SID"
  
  # Get HOST_IP from .env or use localhost
  if [ -f .env ]; then
    HOST_IP=$(grep "^HOST_IP=" .env | cut -d'=' -f2 | tr -d '\n' || echo "localhost")
  else
    HOST_IP="localhost"
  fi
  
  echo ""
  echo "Testing: http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls"
  
  # Try to get API response (without auth, will likely fail but shows if endpoint exists)
  RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" "http://${HOST_IP}:3000/v1/Accounts/${ACCOUNT_SID}/RecentCalls" 2>/dev/null || echo "000")
  
  if [ "$RESPONSE" = "401" ] || [ "$RESPONSE" = "403" ]; then
    echo "✅ API endpoint is accessible (got $RESPONSE - authentication required, which is expected)"
  elif [ "$RESPONSE" = "200" ]; then
    echo "✅ API endpoint is accessible and returning data"
  elif [ "$RESPONSE" = "000" ]; then
    echo "❌ API endpoint is not accessible (connection failed)"
  else
    echo "⚠️  API endpoint returned: $RESPONSE"
  fi
else
  echo "⚠️  Could not find account SID to test"
fi
echo ""

echo "6. Checking Browser Console Errors..."
echo "-----------------------------------"
echo "⚠️  Please check your browser's developer console (F12) for JavaScript errors"
echo "   Common issues:"
echo "   - CORS errors"
echo "   - API endpoint not found (404)"
echo "   - Authentication errors (401/403)"
echo "   - Network errors"
echo ""

echo "=========================================="
echo "Diagnostic Summary"
echo "=========================================="
echo ""
echo "Common fixes for blank call records page:"
echo ""
echo "1. Enable CDRs for your account:"
echo "   sudo docker compose exec mysql mysql -ujambones -pjambones jambones -e \"UPDATE accounts SET disable_cdrs = 0 WHERE account_sid = 'YOUR_ACCOUNT_SID';\""
echo ""
echo "2. Ensure InfluxDB database exists:"
echo "   sudo docker compose exec influxdb influx -execute 'CREATE DATABASE jambones'"
echo ""
echo "3. Check API server logs for errors:"
echo "   sudo docker compose logs api-server --tail 50"
echo ""
echo "4. Check webapp logs for errors:"
echo "   sudo docker compose logs webapp --tail 50"
echo ""
echo "5. Verify API is accessible:"
echo "   curl http://${HOST_IP:-localhost}:3000/v1/Accounts/YOUR_ACCOUNT_SID/RecentCalls"
echo ""

