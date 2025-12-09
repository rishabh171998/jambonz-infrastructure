#!/bin/bash
# Script to pull latest Jambonz Docker images and update services

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
echo "Updating All Jambonz Docker Images"
echo "=========================================="
echo ""
echo "This will pull the latest images for all Jambonz services:"
echo "  - api-server (updated ~20 hours ago)"
echo "  - feature-server (updated ~18 hours ago)"
echo "  - sbc-inbound, sbc-outbound, sbc-call-router, sbc-registrar"
echo "  - webapp"
echo "  - rtpengine"
echo ""
echo "⚠️  Note: This may fix the API response format issue if a newer"
echo "   version has been released."
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo "=== Pulling latest images ==="
echo "This may take a few minutes..."
$DOCKER_CMD pull

echo ""
echo "=== Restarting all services with new images ==="
$DOCKER_CMD up -d

echo ""
echo "=== Waiting for services to start ==="
sleep 10

echo ""
echo "=== Service Status ==="
$DOCKER_CMD ps

echo ""
echo "=== Checking API Server for fixes ==="
echo "Waiting for API server to be ready..."
sleep 5

if [ -f "./debug-api-response.sh" ]; then
  echo ""
  echo "Testing API response format..."
  ./debug-api-response.sh | grep -A 5 "Response Structure" || echo "  Run ./debug-api-response.sh manually to check"
fi

echo ""
echo "=========================================="
echo "Update Complete"
echo "=========================================="
echo ""
echo "All services have been updated to the latest images."
echo ""
echo "Next steps:"
echo "  1. Test a call to verify audio is working"
echo "  2. Check Recent Calls page to see if blank page issue is fixed"
echo "  3. Check logs if issues persist:"
echo "     sudo docker compose logs api-server --tail 50"
echo "     sudo docker compose logs feature-server --tail 50"
echo "     sudo docker compose logs rtpengine --tail 50"
echo ""

