#!/bin/bash
# Script to diagnose "no sound" issue after recording changes

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
echo "Diagnosing No Sound Issue"
echo "=========================================="
echo ""

echo "=== Checking rtpengine configuration ==="
RTPENGINE_CMD=$($DOCKER_CMD exec rtpengine ps aux 2>/dev/null | grep rtpengine | grep -v grep | head -1 || echo "")
if [ -z "$RTPENGINE_CMD" ]; then
  echo "  ❌ Cannot get rtpengine process info"
else
  echo "  rtpengine command:"
  echo "  $RTPENGINE_CMD"
  echo ""
  
  if echo "$RTPENGINE_CMD" | grep -q "listen-ng"; then
    echo "  ✅ --listen-ng parameter found"
  else
    echo "  ❌ --listen-ng parameter MISSING - this is required for SBC communication"
  fi
  
  if echo "$RTPENGINE_CMD" | grep -q "port-min\|port-max"; then
    echo "  ✅ --port-min/--port-max parameters found"
  else
    echo "  ⚠️  --port-min/--port-max parameters not found (may use defaults)"
  fi
fi

echo ""
echo "=== Checking rtpengine logs for errors ==="
$DOCKER_CMD logs rtpengine --tail 30 2>/dev/null | grep -i "error\|fatal\|listen\|port" || echo "  No errors found"

echo ""
echo "=== Checking sbc-inbound logs for RTP errors ==="
$DOCKER_CMD logs sbc-inbound --tail 30 2>/dev/null | grep -i "rtp\|error\|fatal\|rtpengine" | tail -10 || echo "  No RTP errors found"

echo ""
echo "=== Checking feature-server logs for recording interference ==="
$DOCKER_CMD logs feature-server --tail 50 2>/dev/null | grep -i "record\|listen\|audio\|kill\|close" | tail -10 || echo "  No recording issues found"

echo ""
echo "=== Checking if recording WebSocket is closing calls ==="
RECORDING_CLOSES=$($DOCKER_CMD logs feature-server --tail 100 2>/dev/null | grep -i "TaskListen:kill\|closing websocket" | wc -l || echo "0")
if [ "$RECORDING_CLOSES" -gt 0 ]; then
  echo "  ⚠️  Found $RECORDING_CLOSES instances of recording WebSocket being closed"
  echo "     This might be interfering with audio streams"
fi

echo ""
echo "=== Checking API server for recording socket closes ==="
$DOCKER_CMD logs api-server --tail 50 2>/dev/null | grep -i "bucket credential\|close the socket" | tail -5 || echo "  No socket close messages found"

echo ""
echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="
echo ""
echo "Common causes of no sound:"
echo "  1. rtpengine missing --listen-ng parameter"
echo "  2. Recording WebSocket interfering with audio stream"
echo "  3. RTP port range not properly configured"
echo "  4. AWS Security Group blocking RTP ports"
echo ""
echo "To fix:"
echo "  1. Ensure rtpengine has --listen-ng 172.10.0.11:22222"
echo "  2. Check if recording is causing audio stream issues"
echo "  3. Verify AWS Security Group allows UDP 40000-60000"
echo ""

