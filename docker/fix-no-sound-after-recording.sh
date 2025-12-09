#!/bin/bash
# Script to fix "no sound" issue after recording changes
# The issue is likely rtpengine missing --listen-ng parameter

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
echo "Fixing No Sound Issue"
echo "=========================================="
echo ""
echo "The rtpengine is missing the --listen-ng parameter, which is"
echo "required for SBC services to communicate with rtpengine for RTP handling."
echo ""
echo "This script will update docker-compose.yaml to add:"
echo "  - --listen-ng 172.10.0.11:22222"
echo "  - --port-min 40000"
echo "  - --port-max 60000"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# Check current rtpengine command
CURRENT_CMD=$(grep -A 2 "rtpengine:" docker-compose.yaml | grep "command:" | head -1)
echo ""
echo "Current rtpengine command:"
echo "$CURRENT_CMD"
echo ""

# Check if --listen-ng is already present
if echo "$CURRENT_CMD" | grep -q "listen-ng"; then
  echo "✅ --listen-ng is already present in docker-compose.yaml"
  echo "   Restarting rtpengine to apply any changes..."
  $DOCKER_CMD up -d rtpengine
  sleep 3
  echo "✅ rtpengine restarted"
else
  echo "❌ --listen-ng is MISSING"
  echo ""
  echo "Please manually update docker-compose.yaml:"
  echo ""
  echo "Change:"
  echo '  command: ["rtpengine", "--interface", "private/172.10.0.11", "--interface", "public/172.10.0.11!${HOST_IP}", "--log-level", "5"]'
  echo ""
  echo "To:"
  echo '  command: ["rtpengine", "--interface", "private/172.10.0.11", "--interface", "public/172.10.0.11!${HOST_IP}", "--listen-ng", "172.10.0.11:22222", "--port-min", "40000", "--port-max", "60000", "--log-level", "5"]'
  echo ""
  echo "Then run: sudo docker compose up -d rtpengine"
  echo ""
  exit 1
fi

echo ""
echo "=== Verifying rtpengine is running correctly ==="
sleep 2
$DOCKER_CMD ps rtpengine

echo ""
echo "=== Checking rtpengine logs ==="
$DOCKER_CMD logs rtpengine --tail 10 | grep -i "listen\|error\|fatal" || echo "  No errors found"

echo ""
echo "=========================================="
echo "Fix Applied"
echo "=========================================="
echo ""
echo "If sound still doesn't work, check:"
echo "  1. AWS Security Group allows UDP 40000-60000"
echo "  2. sbc-inbound logs: sudo docker compose logs sbc-inbound | grep -i rtp"
echo "  3. rtpengine logs: sudo docker compose logs rtpengine"
echo ""

