#!/bin/bash
# Check API server status and diagnose issues

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
echo "API Server Diagnostic"
echo "=========================================="
echo ""

# Check container status
echo "1. Container Status..."
echo "-------------------------------------------"
$DOCKER_CMD ps | grep api-server || echo "❌ API server container not found"
echo ""

# Check if port is listening inside container
echo "2. Port Listening Check..."
echo "-------------------------------------------"
PORT_CHECK=$($DOCKER_CMD exec api-server netstat -tlnp 2>/dev/null | grep ":3000" || echo "")
if [ -n "$PORT_CHECK" ]; then
  echo "✅ Port 3000 is listening inside container"
  echo "   $PORT_CHECK"
else
  echo "❌ Port 3000 is NOT listening inside container"
fi
echo ""

# Check recent logs for errors
echo "3. Recent Logs (last 50 lines)..."
echo "-------------------------------------------"
$DOCKER_CMD logs --tail 50 api-server 2>&1 | tail -30
echo ""

# Check for error patterns
echo "4. Error Patterns..."
echo "-------------------------------------------"
ERRORS=$($DOCKER_CMD logs --tail 100 api-server 2>&1 | grep -iE "error|fatal|exception|crash|failed" | tail -10 || echo "")
if [ -n "$ERRORS" ]; then
  echo "⚠️  Found errors:"
  echo "$ERRORS"
else
  echo "✅ No obvious errors in recent logs"
fi
echo ""

# Check if process is running
echo "5. Process Check..."
echo "-------------------------------------------"
PROCESS=$($DOCKER_CMD exec api-server ps aux | grep -E "node|app.js" | grep -v grep || echo "")
if [ -n "$PROCESS" ]; then
  echo "✅ Node.js process is running"
  echo "$PROCESS" | head -2
else
  echo "❌ Node.js process NOT running"
fi
echo ""

# Test HTTP endpoint
echo "6. HTTP Endpoint Test..."
echo "-------------------------------------------"
HTTP_TEST=$($DOCKER_CMD exec api-server curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health 2>/dev/null || echo "FAILED")
if [ "$HTTP_TEST" = "200" ] || [ "$HTTP_TEST" = "301" ] || [ "$HTTP_TEST" = "302" ]; then
  echo "✅ HTTP endpoint responding (status: $HTTP_TEST)"
else
  echo "❌ HTTP endpoint not responding (status: $HTTP_TEST)"
fi
echo ""

# Check database connection
echo "7. Database Connection..."
echo "-------------------------------------------"
DB_CHECK=$($DOCKER_CMD exec api-server printenv JAMBONES_MYSQL_HOST 2>/dev/null || echo "")
if [ -n "$DB_CHECK" ]; then
  echo "✅ MySQL host configured: $DB_CHECK"
else
  echo "❌ MySQL host not configured"
fi
echo ""

# Summary and recommendations
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

if [ -z "$PORT_CHECK" ] || [ "$HTTP_TEST" != "200" ]; then
  echo "⚠️  API server appears to be down or not responding"
  echo ""
  echo "Recommended actions:"
  echo "  1. Restart API server: sudo docker compose restart api-server"
  echo "  2. Check full logs: sudo docker compose logs api-server"
  echo "  3. Check for database connection issues"
  echo "  4. Verify environment variables are set correctly"
else
  echo "✅ API server appears to be running"
  echo ""
  echo "If still not accessible from outside:"
  echo "  1. Check AWS Security Group allows port 3000"
  echo "  2. Check firewall rules"
  echo "  3. Verify HOST_IP is correct"
fi
echo ""


