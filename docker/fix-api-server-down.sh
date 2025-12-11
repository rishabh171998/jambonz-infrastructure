#!/bin/bash
# Fix API server that's down or not responding

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
echo "Fix API Server"
echo "=========================================="
echo ""

# Check current status
echo "1. Checking Current Status..."
echo "-------------------------------------------"
CONTAINER_STATUS=$($DOCKER_CMD ps --format "{{.Status}}" --filter "name=api-server" 2>/dev/null || echo "")
if [ -z "$CONTAINER_STATUS" ]; then
  echo "❌ API server container not running"
  echo "   Starting container..."
  $DOCKER_CMD up -d api-server
  sleep 5
else
  echo "✅ Container is running: $CONTAINER_STATUS"
fi
echo ""

# Check if port is listening
echo "2. Checking Port 3000..."
echo "-------------------------------------------"
sleep 2
PORT_CHECK=$($DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "")
if [ -z "$PORT_CHECK" ]; then
  echo "⚠️  Port 3000 not listening, restarting..."
  $DOCKER_CMD restart api-server
  echo "   Waiting for API server to start..."
  sleep 10
  
  # Check again
  PORT_CHECK=$($DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "")
  if [ -z "$PORT_CHECK" ]; then
    echo "❌ Port still not listening after restart"
    echo ""
    echo "Checking logs for errors..."
    $DOCKER_CMD logs --tail 30 api-server
    exit 1
  else
    echo "✅ Port 3000 is now listening"
  fi
else
  echo "✅ Port 3000 is listening"
fi
echo ""

# Test HTTP endpoint
echo "3. Testing HTTP Endpoint..."
echo "-------------------------------------------"
HTTP_TEST=$($DOCKER_CMD exec api-server curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "FAILED")
if [ "$HTTP_TEST" = "200" ] || [ "$HTTP_TEST" = "301" ] || [ "$HTTP_TEST" = "302" ]; then
  echo "✅ HTTP endpoint responding (status: $HTTP_TEST)"
else
  echo "⚠️  HTTP endpoint not responding (status: $HTTP_TEST)"
  echo "   Checking recent logs..."
  $DOCKER_CMD logs --tail 20 api-server | tail -10
  echo ""
  echo "   Attempting restart..."
  $DOCKER_CMD restart api-server
  sleep 10
  echo "   Testing again..."
  HTTP_TEST=$($DOCKER_CMD exec api-server curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "FAILED")
  if [ "$HTTP_TEST" = "200" ] || [ "$HTTP_TEST" = "301" ] || [ "$HTTP_TEST" = "302" ]; then
    echo "✅ HTTP endpoint now responding"
  else
    echo "❌ HTTP endpoint still not responding"
    echo "   Check logs: sudo docker compose logs api-server"
  fi
fi
echo ""

# Check database connection
echo "4. Verifying Database Connection..."
echo "-------------------------------------------"
DB_HOST=$($DOCKER_CMD exec api-server printenv JAMBONES_MYSQL_HOST 2>/dev/null || echo "")
if [ -z "$DB_HOST" ]; then
  echo "❌ JAMBONES_MYSQL_HOST not set"
else
  echo "✅ MySQL host: $DB_HOST"
  
  # Test database connection
  DB_TEST=$($DOCKER_CMD exec api-server sh -c "timeout 2 nc -z $DB_HOST 3306 2>/dev/null && echo 'OK' || echo 'FAILED'" 2>/dev/null || echo "FAILED")
  if [ "$DB_TEST" = "OK" ]; then
    echo "✅ Database is reachable"
  else
    echo "⚠️  Cannot reach database at $DB_HOST:3306"
    echo "   This may cause API server to fail"
  fi
fi
echo ""

# Final status
echo "=========================================="
echo "✅ API Server Fix Complete"
echo "=========================================="
echo ""
echo "Status:"
echo "  - Container: Running"
echo "  - Port 3000: $([ -n "$PORT_CHECK" ] && echo "Listening ✅" || echo "Not listening ❌")"
echo "  - HTTP: $([ "$HTTP_TEST" = "200" ] && echo "Responding ✅" || echo "Not responding ⚠️")"
echo ""
echo "If still not accessible from http://15.207.113.122:3000:"
echo "  1. Check AWS Security Group allows inbound on port 3000"
echo "  2. Verify HOST_IP is set correctly: echo \$HOST_IP"
echo "  3. Check full logs: sudo docker compose logs api-server"
echo ""


