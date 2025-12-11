#!/bin/bash
# Fix blank Swagger page

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
echo "Fixing Blank Swagger Page"
echo "=========================================="
echo ""

# 1. Restart API server
echo "1. Restarting API Server..."
echo "-------------------------------------------"
$DOCKER_CMD restart api-server
echo "   Waiting for API server to start..."
sleep 5

# Check if it's running
if $DOCKER_CMD ps | grep -q "api-server"; then
  echo "   ✅ API server restarted"
else
  echo "   ❌ API server failed to start"
  echo "   Check logs: sudo docker compose logs api-server"
  exit 1
fi
echo ""

# 2. Test Swagger endpoint
echo "2. Testing Swagger Endpoint..."
echo "-------------------------------------------"
HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

echo "   Testing: http://${HOST_IP}:3000/swagger/"
SWAGGER_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger/" 2>/dev/null || echo "000")

if [ "$SWAGGER_TEST" = "200" ]; then
  echo "   ✅ Swagger endpoint returns HTTP 200"
else
  echo "   ⚠️  Swagger endpoint returned HTTP $SWAGGER_TEST"
fi
echo ""

# 3. Check API server logs
echo "3. Recent API Server Logs:"
echo "-------------------------------------------"
$DOCKER_CMD logs --tail 20 api-server 2>/dev/null | tail -10
echo ""

# 4. Test localhost access
echo "4. Testing Localhost Access..."
echo "-------------------------------------------"
LOCAL_TEST=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:3000/swagger/" 2>/dev/null || echo "000")
if [ "$LOCAL_TEST" = "200" ]; then
  echo "   ✅ Swagger accessible on localhost"
  echo "   This suggests the issue is with external access or DNS"
else
  echo "   ⚠️  Swagger not accessible on localhost (HTTP $LOCAL_TEST)"
fi
echo ""

echo "=========================================="
echo "Troubleshooting Steps"
echo "=========================================="
echo ""
echo "If Swagger is still blank:"
echo ""
echo "1. Check Browser Console (F12 → Console tab):"
echo "   - Look for JavaScript errors"
echo "   - Look for CORS errors"
echo "   - Look for failed network requests"
echo ""
echo "2. Check Network Tab (F12 → Network tab):"
echo "   - Reload the page"
echo "   - Check if swagger.json is loading"
echo "   - Check if CSS/JS files are loading"
echo ""
echo "3. Try Alternative URLs:"
echo "   - http://${HOST_IP}:3000/swagger"
echo "   - http://${HOST_IP}:3000/api/v1"
echo "   - http://sip.graine.ai:3000/swagger/"
echo ""
echo "4. Check DNS:"
echo "   - Verify sip.graine.ai resolves to ${HOST_IP}"
echo "   - Try using IP directly: http://${HOST_IP}:3000/swagger/"
echo ""
echo "5. Check Proxy/Load Balancer:"
echo "   - If using a proxy, ensure it's not interfering"
echo "   - Check if proxy is stripping headers"
echo ""
echo "6. Check API Server Logs:"
echo "   sudo docker compose logs -f api-server"
echo ""

