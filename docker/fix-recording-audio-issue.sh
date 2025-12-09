#!/bin/bash
# Script to fix "no sound" issue caused by recording configuration
# The issue is likely that recording is interfering with the audio stream

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
echo "Fixing Recording Audio Interference Issue"
echo "=========================================="
echo ""
echo "The issue: Recording WebSocket is closing immediately, which might"
echo "be interfering with the main audio stream."
echo ""
echo "Looking at the logs, the recording WebSocket closes because:"
echo "  - API server says 'account does not have any bucket credential'"
echo "  - But this is for a different account (9351f46a-...), not yours"
echo ""
echo "Options:"
echo "  1. Temporarily disable recording to restore audio"
echo "  2. Fix the recording WebSocket configuration"
echo "  3. Check if recording is consuming the audio stream incorrectly"
echo ""

read -p "Choose option (1/2/3): " -r
echo ""

case $REPLY in
  1)
    echo "=== Temporarily Disabling Recording ==="
    echo ""
    echo "This will disable recording at the account level in the database."
    echo "You can re-enable it later from the webapp."
    echo ""
    read -p "Continue? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Cancelled."
      exit 0
    fi
    
    # Get account SID
    ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts WHERE name = 'GraineAI' LIMIT 1;" 2>/dev/null || echo "")
    if [ -z "$ACCOUNT_SID" ]; then
      ACCOUNT_SID=$($DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones -N -e "SELECT account_sid FROM accounts LIMIT 1;" 2>/dev/null || echo "")
    fi
    
    if [ -z "$ACCOUNT_SID" ]; then
      echo "ERROR: Could not find account SID"
      exit 1
    fi
    
    echo "Disabling recording for account: $ACCOUNT_SID"
    $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0 WHERE account_sid = '$ACCOUNT_SID';
EOF
    
    echo "✅ Recording disabled. Restarting feature-server..."
    $DOCKER_CMD restart feature-server
    echo ""
    echo "✅ Done. Test a call now. Audio should work."
    echo "   To re-enable recording: Go to webapp -> Accounts -> Edit Account"
    ;;
    
  2)
    echo "=== Checking Recording WebSocket Configuration ==="
    echo ""
    echo "Current feature-server recording config:"
    $DOCKER_CMD exec feature-server env | grep -i "JAMBONZ_RECORD" || echo "  No JAMBONZ_RECORD env vars found"
    echo ""
    echo "Current api-server recording config:"
    $DOCKER_CMD exec api-server env | grep -i "JAMBONZ_RECORD" || echo "  No JAMBONZ_RECORD env vars found"
    echo ""
    echo "Check the logs to see why the WebSocket is closing:"
    echo "  sudo docker compose logs api-server | grep -i 'bucket credential\|close the socket'"
    ;;
    
  3)
    echo "=== Checking if Recording is Interfering with Audio ==="
    echo ""
    echo "Recent feature-server recording activity:"
    $DOCKER_CMD logs feature-server --tail 100 2>/dev/null | grep -i "record\|listen\|audio\|kill\|close" | tail -20
    echo ""
    echo "Recent api-server recording activity:"
    $DOCKER_CMD logs api-server --tail 100 2>/dev/null | grep -i "record\|bucket\|socket\|close" | tail -20
    echo ""
    echo "If you see 'TaskListen:kill closing websocket' frequently,"
    echo "the recording might be interfering with the main audio stream."
    ;;
    
  *)
    echo "Invalid option. Exiting."
    exit 1
    ;;
esac

echo ""
echo "=========================================="
echo "Diagnosis Complete"
echo "=========================================="

