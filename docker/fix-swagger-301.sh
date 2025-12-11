#!/bin/bash
# Fix Swagger HTTP 301 redirect issue

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
echo "Fixing Swagger HTTP 301 Redirect"
echo "=========================================="
echo ""

HOST_IP=$(grep "^HOST_IP=" .env 2>/dev/null | cut -d'=' -f2 || echo "")
if [ -z "$HOST_IP" ]; then
  HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
fi

echo "Testing Swagger endpoints..."
echo ""

# Test different URLs
echo "1. Testing /swagger (without trailing slash):"
SWAGGER1=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger" 2>/dev/null || echo "000")
echo "   HTTP Status: $SWAGGER1"
if [ "$SWAGGER1" = "301" ]; then
  echo "   ⚠️  HTTP 301 redirect detected"
  echo "   Following redirect..."
  REDIRECT_URL=$(curl -s -o /dev/null -w "%{redirect_url}" --max-time 5 "http://${HOST_IP}:3000/swagger" 2>/dev/null || echo "")
  if [ -n "$REDIRECT_URL" ]; then
    echo "   Redirects to: $REDIRECT_URL"
  fi
fi
echo ""

echo "2. Testing /swagger/ (with trailing slash):"
SWAGGER2=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/swagger/" 2>/dev/null || echo "000")
echo "   HTTP Status: $SWAGGER2"
echo ""

echo "3. Testing root /:"
ROOT=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/" 2>/dev/null || echo "000")
echo "   HTTP Status: $ROOT"
echo ""

echo "4. Testing /api/v1 (API endpoint):"
API=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://${HOST_IP}:3000/api/v1" 2>/dev/null || echo "000")
echo "   HTTP Status: $API"
echo ""

# Check if API server is behind a proxy
echo "5. Checking JAMBONES_TRUST_PROXY:"
TRUST_PROXY=$($DOCKER_CMD exec api-server printenv JAMBONES_TRUST_PROXY 2>/dev/null || echo "")
if [ -n "$TRUST_PROXY" ]; then
  echo "   JAMBONES_TRUST_PROXY: $TRUST_PROXY"
else
  echo "   JAMBONES_TRUST_PROXY: not set"
fi
echo ""

# Check API server logs for redirects
echo "6. Checking API server logs for redirects:"
REDIRECT_LOGS=$($DOCKER_CMD logs --tail 50 api-server 2>/dev/null | grep -iE "301|redirect|swagger" | tail -5 || echo "")
if [ -n "$REDIRECT_LOGS" ]; then
  echo "$REDIRECT_LOGS" | sed 's/^/   /'
else
  echo "   No redirect logs found"
fi
echo ""

echo "=========================================="
echo "Solution"
echo "=========================================="
echo ""

if [ "$SWAGGER2" = "200" ]; then
  echo "✅ Use URL with trailing slash:"
  echo "   http://${HOST_IP}:3000/swagger/"
elif [ "$SWAGGER1" = "301" ] && [ -n "$REDIRECT_URL" ]; then
  echo "✅ Follow the redirect:"
  echo "   $REDIRECT_URL"
else
  echo "Try these URLs:"
  echo "  1. http://${HOST_IP}:3000/swagger/"
  echo "  2. http://${HOST_IP}:3000/swagger"
  echo "  3. http://${HOST_IP}:3000/api/v1"
  echo ""
  echo "If still not working:"
  echo "  1. Check API server logs: sudo docker compose logs api-server"
  echo "  2. Verify security group allows port 3000"
  echo "  3. Test locally: curl http://localhost:3000/swagger/"
fi
echo ""

