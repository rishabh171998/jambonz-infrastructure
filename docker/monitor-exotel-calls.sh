#!/bin/bash
# Monitor Exotel calls in real-time - show full INVITE messages

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
echo "Monitoring Exotel Calls - Real-time Logs"
echo "=========================================="
echo ""
echo "This will show:"
echo "  - Full SIP INVITE messages from Exotel"
echo "  - Request URI (what Jambonz uses for routing)"
echo "  - To/From headers"
echo "  - Any errors"
echo ""
echo "Make a test call from Exotel now..."
echo "Press Ctrl+C to stop"
echo ""
echo "=========================================="
echo ""

# Monitor drachtio-sbc logs for INVITE
$DOCKER_CMD logs -f drachtio-sbc 2>&1 | while IFS= read -r line; do
  # Look for INVITE messages
  if echo "$line" | grep -qi "invite"; then
    echo ">>> INVITE DETECTED <<<"
    echo "$line"
    # Show next 20 lines to get full message
    for i in {1..20}; do
      read -r next_line || break
      echo "$next_line"
      # Stop if we hit an empty line or another SIP message
      if [[ -z "$next_line" ]] || echo "$next_line" | grep -qE "^[A-Z]"; then
        break
      fi
    done
    echo ""
    echo "---"
    echo ""
  fi
  
  # Also show 404 errors
  if echo "$line" | grep -qi "404\|not found"; then
    echo ">>> 404 ERROR <<<"
    echo "$line"
    echo ""
  fi
done

