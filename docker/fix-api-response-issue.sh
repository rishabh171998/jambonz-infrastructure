#!/bin/bash
# Script to attempt to fix the API response format issue by updating the API server

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
echo "Attempting to Fix API Response Issue"
echo "=========================================="
echo ""
echo "This script will:"
echo "  1. Pull the latest API server image"
echo "  2. Restart the API server"
echo "  3. Test the API response format"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

echo ""
echo "Step 1: Pulling latest API server image..."
$DOCKER_CMD pull api-server

echo ""
echo "Step 2: Restarting API server..."
$DOCKER_CMD up -d api-server

echo ""
echo "Waiting for API server to be ready..."
sleep 5

echo ""
echo "Step 3: Testing API response format..."
if [ -f "./debug-api-response.sh" ]; then
  ./debug-api-response.sh
else
  echo "  ⚠️  debug-api-response.sh not found, skipping test"
fi

echo ""
echo "=========================================="
echo "Update Complete"
echo "=========================================="
echo ""
echo "If the issue persists, it means the bug hasn't been fixed in the latest"
echo "API server image yet. This is a known issue in the jambonz/api-server"
echo "codebase where the RecentCalls endpoint returns 'page_size' instead of 'batch'."
echo ""
echo "See API_RESPONSE_ISSUE.md for more details."
echo ""

