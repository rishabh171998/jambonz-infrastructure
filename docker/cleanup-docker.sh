#!/bin/bash
# Clean up Docker resources to free disk space

set -e

echo "=========================================="
echo "Docker Cleanup"
echo "=========================================="
echo ""

# Check if we need sudo
if ! docker ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
else
  DOCKER_CMD="docker"
fi

# Show current usage
echo "1. Current Docker Disk Usage..."
echo "-------------------------------------------"
$DOCKER_CMD system df
echo ""

# Remove stopped containers
echo "2. Removing Stopped Containers..."
echo "-------------------------------------------"
STOPPED=$($DOCKER_CMD ps -a --filter "status=exited" -q 2>/dev/null || echo "")
if [ -n "$STOPPED" ]; then
  echo "Found stopped containers, removing..."
  $DOCKER_CMD rm $STOPPED 2>/dev/null || echo "Some containers couldn't be removed (may be in use)"
  echo "✅ Stopped containers removed"
else
  echo "✅ No stopped containers to remove"
fi
echo ""

# Remove unused images (dangling)
echo "3. Removing Dangling Images..."
echo "-------------------------------------------"
DANGLING=$($DOCKER_CMD images -f "dangling=true" -q 2>/dev/null || echo "")
if [ -n "$DANGLING" ]; then
  echo "Found dangling images, removing..."
  $DOCKER_CMD rmi $DANGLING 2>/dev/null || echo "Some images couldn't be removed"
  echo "✅ Dangling images removed"
else
  echo "✅ No dangling images to remove"
fi
echo ""

# Remove unused images (not tagged)
echo "4. Removing Unused Images..."
echo "-------------------------------------------"
echo "⚠️  This will remove images not used by any container"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  $DOCKER_CMD image prune -a -f
  echo "✅ Unused images removed"
else
  echo "⏭️  Skipped"
fi
echo ""

# Clean build cache
echo "5. Cleaning Build Cache..."
echo "-------------------------------------------"
echo "⚠️  This will remove all build cache"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  $DOCKER_CMD builder prune -a -f
  echo "✅ Build cache cleaned"
else
  echo "⏭️  Skipped"
fi
echo ""

# Remove unused volumes
echo "6. Removing Unused Volumes..."
echo "-------------------------------------------"
echo "⚠️  This will remove volumes not used by any container"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  $DOCKER_CMD volume prune -f
  echo "✅ Unused volumes removed"
else
  echo "⏭️  Skipped"
fi
echo ""

# Remove unused networks
echo "7. Removing Unused Networks..."
echo "-------------------------------------------"
$DOCKER_CMD network prune -f
echo "✅ Unused networks removed"
echo ""

# System prune (everything unused)
echo "8. Full System Prune..."
echo "-------------------------------------------"
echo "⚠️  This will remove ALL unused Docker resources"
read -p "Continue? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  $DOCKER_CMD system prune -a -f --volumes
  echo "✅ Full system prune completed"
else
  echo "⏭️  Skipped"
fi
echo ""

# Show final usage
echo "=========================================="
echo "Final Docker Disk Usage"
echo "=========================================="
$DOCKER_CMD system df
echo ""

# Check overall disk space
echo "=========================================="
echo "Overall Disk Space"
echo "=========================================="
df -h /
echo ""

echo "✅ Cleanup complete!"
echo ""

