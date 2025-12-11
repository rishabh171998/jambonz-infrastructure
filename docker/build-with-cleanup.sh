#!/bin/bash
# Build Docker images with automatic cleanup during build

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

# Check Docker command
if ! docker ps &> /dev/null 2>&1; then
  DOCKER_BASE="sudo docker"
else
  DOCKER_BASE="docker"
fi

echo "=========================================="
echo "Build with Cleanup"
echo "=========================================="
echo ""

# Check disk space before
echo "1. Disk Space Before Build..."
echo "-------------------------------------------"
df -h /
AVAILABLE_BEFORE=$(df / | tail -1 | awk '{print $4}' | sed 's/[^0-9]//g')
echo ""

# Clean up before build
echo "2. Pre-Build Cleanup..."
echo "-------------------------------------------"
$DOCKER_BASE system prune -f
$DOCKER_BASE builder prune -f
echo ""

# Get service name from argument or default to webapp
SERVICE=${1:-webapp}

echo "3. Building $SERVICE..."
echo "-------------------------------------------"
echo "⚠️  This will clean up during build if needed"
echo ""

# Function to check and cleanup if needed
check_and_cleanup() {
  AVAILABLE=$(df / | tail -1 | awk '{print $4}' | sed 's/[^0-9]//g')
  if [ "$AVAILABLE" -lt 2000000 ]; then  # Less than 2GB
    echo ""
    echo "⚠️  Low disk space detected, cleaning up..."
    $DOCKER_BASE system prune -f
    $DOCKER_BASE builder prune -f
    df -h / | tail -1
    echo ""
  fi
}

# Build with periodic cleanup
echo "Starting build..."
$DOCKER_CMD build --progress=plain $SERVICE 2>&1 | while IFS= read -r line; do
  echo "$line"
  # Check every 50 lines
  if (( $(echo "$line" | grep -c "Step\|Layer\|Exporting" || echo "0") > 0 )); then
    check_and_cleanup
  fi
done

BUILD_EXIT=${PIPESTATUS[0]}

# Check disk space after
echo ""
echo "4. Disk Space After Build..."
echo "-------------------------------------------"
df -h /
echo ""

if [ $BUILD_EXIT -eq 0 ]; then
  echo "✅ Build completed successfully!"
else
  echo "❌ Build failed with exit code $BUILD_EXIT"
  echo ""
  echo "If you ran out of space, try:"
  echo "  1. Run: sudo ./emergency-cleanup.sh"
  echo "  2. Then rebuild: sudo docker compose build $SERVICE"
  exit $BUILD_EXIT
fi

