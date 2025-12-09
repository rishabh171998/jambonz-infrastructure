#!/bin/bash
# Quick script to fix RTP/no sound issue by restarting rtpengine with correct config

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
echo "Fixing RTP/No Sound Issue"
echo "=========================================="
echo ""
echo "The rtpengine was missing required parameters:"
echo "  - --listen-ng (control interface)"
echo "  - --port-min and --port-max (RTP port range)"
echo ""
echo "Restarting rtpengine with correct configuration..."
echo ""

$DOCKER_CMD up -d rtpengine

echo ""
echo "Waiting for rtpengine to start..."
sleep 3

echo ""
echo "Checking rtpengine status..."
$DOCKER_CMD ps rtpengine

echo ""
echo "Checking rtpengine logs for errors..."
$DOCKER_CMD logs rtpengine --tail 20 | grep -i "error\|fatal\|listen-ng\|port" || echo "  No errors found in recent logs"

echo ""
echo "=========================================="
echo "RTP Engine Restarted"
echo "=========================================="
echo ""
echo "If sound still doesn't work, check:"
echo "  1. AWS Security Group allows UDP 40000-60000"
echo "  2. rtpengine logs: sudo docker compose logs rtpengine"
echo "  3. sbc-inbound logs: sudo docker compose logs sbc-inbound | grep -i rtp"
echo ""

