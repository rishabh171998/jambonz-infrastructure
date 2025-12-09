#!/bin/bash
# Disable recording until the bug is fixed
# This is the ONLY safe workaround

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
echo "Disabling Recording (Bug Workaround)"
echo "=========================================="
echo ""
echo "There is a bug in jambonz/feature-server where it sends"
echo "the wrong account_sid to the API server when recording."
echo ""
echo "This causes:"
echo "  - Recording WebSocket to close immediately"
echo "  - Main audio stream to be killed"
echo "  - No audio in calls"
echo ""
echo "The proper fix requires updating jambonz/feature-server code."
echo "Until then, recording must be disabled."
echo ""

read -p "Disable recording for all accounts? (y/n) " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo ""
  echo "Disabling recording for all accounts..."
  $DOCKER_CMD exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE accounts SET record_all_calls = 0;
EOF
  
  echo "✅ Recording disabled for all accounts."
  echo ""
  echo "Restarting feature-server..."
  $DOCKER_CMD restart feature-server
  
  echo ""
  echo "✅ Done. Audio should work now (but no recording)."
  echo ""
  echo "See RECORDING_AUDIO_BUG.md for details on the bug."
  echo ""
  echo "To re-enable recording after the bug is fixed:"
  echo "  UPDATE accounts SET record_all_calls = 1 WHERE account_sid = 'bed525b4-af09-40d2-9fe7-cdf6ae577c69';"
else
  echo ""
  echo "Cancelled. Recording remains enabled."
  echo "Calls will have no audio until this bug is fixed."
fi

