#!/bin/bash
# Fix Swagger access issue

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
echo "Fixing Swagger Access"
echo "=========================================="
echo ""

# 1. Check API server is running
echo "1. Checking API Server Status..."
echo "-------------------------------------------"
if $DOCKER_CMD ps | grep -q "api-server"; then
  echo "✅ API server is running"
else
  echo "❌ API server is NOT running"
  echo "Starting api-server..."
  $DOCKER_CMD up -d api-server
  sleep 5
fi
echo ""

# 2. Check port mapping
echo "2. Checking Port Mapping..."
echo "-------------------------------------------"
PORT_MAP=$($DOCKER_CMD ps --format "{{.Ports}}" | grep api-server || echo "")
if echo "$PORT_MAP" | grep -q "3000:3000"; then
  echo "✅ Port 3000 is mapped correctly"
else
  echo "❌ Port 3000 not mapped correctly"
  echo "   Current mapping: $PORT_MAP"
  echo ""
  echo "⚠️  Check docker-compose.yaml - api-server should have:"
  echo "   ports:"
  echo "     - \"3000:3000\""
fi
echo ""

# 3. Check API server is listening
echo "3. Checking API Server Listening..."
echo "-------------------------------------------"
LISTEN_CHECK=$($DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "")
if echo "$LISTEN_CHECK" | grep -q "0.0.0.0:3000"; then
  echo "✅ API server is listening on 0.0.0.0:3000"
elif echo "$LISTEN_CHECK" | grep -q ":3000"; then
  echo "⚠️  API server is listening but may not be on 0.0.0.0"
  echo "   $LISTEN_CHECK"
  echo ""
  echo "   Restarting api-server to ensure proper binding..."
  $DOCKER_CMD restart api-server
  sleep 5
else
  echo "❌ API server is NOT listening on port 3000"
  echo "   Checking logs..."
  $DOCKER_CMD logs --tail 20 api-server
fi
echo ""

# 4. Test localhost access
echo "4. Testing Localhost Access..."
echo "-------------------------------------------"
LOCAL_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:3000/swagger" 2>/dev/null || echo "000")
if [ "$LOCAL_TEST" = "200" ]; then
  echo "✅ Swagger accessible on localhost"
elif [ "$LOCAL_TEST" = "000" ]; then
  echo "❌ Cannot connect to localhost:3000"
  echo "   API server may not be running or not listening"
else
  echo "⚠️  Swagger returned HTTP $LOCAL_TEST"
  echo "   (This may be normal if authentication is required)"
fi
echo ""

# 5. Get HOST_IP and test external access
echo "5. Testing External Access..."
echo "-------------------------------------------"
HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

if [ -n "$HOST_IP" ]; then
  echo "   HOST_IP: $HOST_IP"
  echo "   Testing: http://${HOST_IP}:3000/swagger"
  EXTERNAL_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger" 2>/dev/null || echo "000")
  if [ "$EXTERNAL_TEST" = "200" ]; then
    echo "   ✅ Swagger accessible externally"
  elif [ "$EXTERNAL_TEST" = "000" ]; then
    echo "   ❌ Cannot connect externally"
    echo ""
    echo "   ⚠️  Check AWS Security Group:"
    echo "      - Inbound rule for TCP port 3000"
    echo "      - Source: Your IP or 0.0.0.0/0 (for testing)"
  else
    echo "   ⚠️  Swagger returned HTTP $EXTERNAL_TEST"
  fi
else
  echo "   ⚠️  Could not determine HOST_IP"
fi
echo ""

# 6. Check API server logs for errors
echo "6. Checking API Server Logs..."
echo "-------------------------------------------"
RECENT_ERRORS=$($DOCKER_CMD logs --tail 30 api-server 2>/dev/null | grep -iE "error|fail|swagger" | tail -5 || echo "")
if [ -n "$RECENT_ERRORS" ]; then
  echo "   Recent errors/warnings:"
  echo "$RECENT_ERRORS" | sed 's/^/   /'
else
  echo "   ✅ No recent errors found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "Swagger URL: http://${HOST_IP:-<HOST_IP>}:3000/swagger"
echo ""
echo "If swagger is still not accessible:"
echo "  1. Check AWS Security Group allows TCP 3000"
echo "  2. Verify API server is running: sudo docker compose ps api-server"
echo "  3. Check logs: sudo docker compose logs api-server"
echo "  4. Test locally: curl http://localhost:3000/swagger"
echo ""
echo "Note: Swagger requires Bearer token authentication"
echo "      Generate token using create-admin-token.sql"
echo ""

