#!/bin/bash
# Check disk space and Docker usage

set -e

echo "=========================================="
echo "Disk Space Check"
echo "=========================================="
echo ""

# Check overall disk usage
echo "1. Overall Disk Usage..."
echo "-------------------------------------------"
df -h /
echo ""

# Check Docker disk usage
echo "2. Docker Disk Usage..."
echo "-------------------------------------------"
if command -v docker &> /dev/null; then
  if sudo docker system df &> /dev/null; then
    sudo docker system df
  else
    docker system df
  fi
else
  echo "Docker not found"
fi
echo ""

# Check largest directories
echo "3. Largest Directories (top 10)..."
echo "-------------------------------------------"
du -h --max-depth=1 / 2>/dev/null | sort -rh | head -10 || echo "Cannot check (permission denied)"
echo ""

# Check Docker images
echo "4. Docker Images (sorted by size)..."
echo "-------------------------------------------"
if command -v docker &> /dev/null; then
  if sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" &> /dev/null; then
    sudo docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | head -20
  else
    docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}" | head -20
  fi
fi
echo ""

# Check for stopped containers
echo "5. Stopped Containers..."
echo "-------------------------------------------"
if command -v docker &> /dev/null; then
  STOPPED=$(sudo docker ps -a --filter "status=exited" --format "{{.ID}}" 2>/dev/null | wc -l || echo "0")
  echo "Found $STOPPED stopped containers"
fi
echo ""

# Summary
echo "=========================================="
echo "Summary"
echo "=========================================="
USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$USAGE" -gt 90 ]; then
  echo "⚠️  Disk usage is CRITICAL: ${USAGE}%"
  echo ""
  echo "Recommended actions:"
  echo "  1. Run: sudo ./cleanup-docker.sh"
  echo "  2. Remove unused Docker images and containers"
  echo "  3. Clean Docker build cache"
  echo "  4. Remove old logs if any"
elif [ "$USAGE" -gt 80 ]; then
  echo "⚠️  Disk usage is HIGH: ${USAGE}%"
  echo "   Consider cleaning up Docker resources"
else
  echo "✅ Disk usage is OK: ${USAGE}%"
fi
echo ""

