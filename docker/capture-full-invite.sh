#!/bin/bash
# Capture full INVITE message from Exotel

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
echo "Capturing Full Exotel INVITE"
echo "=========================================="
echo ""
echo "Make a test call from Exotel NOW..."
echo "This will capture the full INVITE message"
echo ""
echo "Waiting for INVITE..."
echo ""

# Capture INVITE with context
$DOCKER_CMD logs -f drachtio-sbc 2>&1 | while IFS= read -r line; do
  if echo "$line" | grep -qi "INVITE.*sip:"; then
    echo "=========================================="
    echo ">>> INVITE CAPTURED <<<"
    echo "=========================================="
    echo ""
    echo "$line"
    
    # Read next 25 lines to get full message
    for i in {1..25}; do
      read -r next_line || break
      echo "$next_line"
    done
    
    echo ""
    echo "=========================================="
    echo "Key Information:"
    echo "=========================================="
    echo ""
    echo "Look for the Request URI (first line after 'INVITE'):"
    echo "  - Should be: sip:+918064061518@... or sip:08064061518@..."
    echo "  - If it's: sip:1219300017707497486@... then Exotel destination URI needs fixing"
    echo ""
    break
  fi
done

