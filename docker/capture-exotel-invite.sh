#!/bin/bash
# Capture full Exotel INVITE to see Request URI

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
echo "Capturing Exotel INVITE (Full Message)"
echo "=========================================="
echo ""
echo "Make a test call from Exotel now..."
echo "Then press Ctrl+C to stop"
echo ""
echo "Looking for INVITE messages..."
echo ""

# Monitor for INVITE and show full message
$DOCKER_CMD logs -f drachtio-sbc 2>&1 | grep --line-buffered -A 30 "INVITE" | grep --line-buffered -E "INVITE|Request URI|To:|From:|Call-ID|^sip:" || {
  echo ""
  echo "No INVITE captured. Make a test call from Exotel."
}

