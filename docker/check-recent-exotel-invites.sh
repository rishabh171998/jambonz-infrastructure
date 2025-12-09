#!/bin/bash
# Check recent Exotel INVITEs from logs

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
echo "Recent Exotel INVITEs (Last 5 minutes)"
echo "=========================================="
echo ""

# Get recent INVITE messages
echo "Looking for INVITE messages..."
echo ""

# Get logs and extract INVITE sections
$DOCKER_CMD logs --since 5m drachtio-sbc 2>&1 | grep -A 25 "INVITE" | head -100 || echo "No INVITE messages found in last 5 minutes"

echo ""
echo "=========================================="
echo "Key Information to Look For"
echo "=========================================="
echo ""
echo "1. Request URI (first line after INVITE):"
echo "   Should be: sip:+918064061518@... or sip:08064061518@..."
echo "   NOT: sip:1219300017707497486@..."
echo ""
echo "2. To header:"
echo "   Should contain your phone number"
echo ""
echo "3. Response:"
echo "   Look for 200 OK (success) or 404 Not Found (routing issue)"
echo ""

