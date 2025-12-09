#!/bin/bash
# View Exotel call logs - simple version

set -e

cd "$(dirname "$0")"

# Determine docker compose command
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_CMD="docker-compose"
else
  DOCKER_CMD="docker-compose"
fi

# Check if we need sudo
if ! $DOCKER_CMD ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo $DOCKER_CMD"
fi

echo "=========================================="
echo "Exotel Call Logs - Last 100 Lines"
echo "=========================================="
echo ""

# Show last 100 lines
$DOCKER_CMD logs --tail 100 drachtio-sbc 2>&1

echo ""
echo "=========================================="
echo "To monitor in real-time:"
echo "  sudo docker compose logs -f drachtio-sbc"
echo ""

