#!/bin/bash
# Aggressive Docker cleanup - removes everything unused without prompts

set -e

echo "=========================================="
echo "Aggressive Docker Cleanup"
echo "=========================================="
echo "⚠️  This will remove ALL unused Docker resources"
echo ""

# Check if we need sudo
if ! docker ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
else
  DOCKER_CMD="docker"
fi

# Show current usage
echo "1. Current Disk Usage..."
echo "-------------------------------------------"
df -h /
echo ""
$DOCKER_CMD system df
echo ""

# Remove stopped containers
echo "2. Removing Stopped Containers..."
$DOCKER_CMD container prune -f
echo ""

# Remove unused images
echo "3. Removing Unused Images..."
$DOCKER_CMD image prune -a -f
echo ""

# Clean build cache
echo "4. Cleaning Build Cache..."
$DOCKER_CMD builder prune -a -f
echo ""

# Remove unused volumes
echo "5. Removing Unused Volumes..."
$DOCKER_CMD volume prune -f
echo ""

# Remove unused networks
echo "6. Removing Unused Networks..."
$DOCKER_CMD network prune -f
echo ""

# Full system prune
echo "7. Full System Prune..."
$DOCKER_CMD system prune -a -f --volumes
echo ""

# Show final usage
echo "=========================================="
echo "Final Disk Usage"
echo "=========================================="
df -h /
echo ""
$DOCKER_CMD system df
echo ""

echo "✅ Aggressive cleanup complete!"
echo ""

