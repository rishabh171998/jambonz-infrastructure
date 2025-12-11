#!/bin/bash
# Emergency cleanup - most aggressive cleanup possible

set -e

echo "=========================================="
echo "EMERGENCY DISK CLEANUP"
echo "=========================================="
echo "⚠️  This will aggressively clean everything possible"
echo ""

# Check if we need sudo
if ! docker ps &> /dev/null 2>&1; then
  DOCKER_CMD="sudo docker"
  SUDO_CMD="sudo"
else
  DOCKER_CMD="docker"
  SUDO_CMD=""
fi

# Show current usage
echo "1. Current Disk Usage..."
df -h /
echo ""

# Stop all containers to free up space
echo "2. Stopping All Containers..."
echo "-------------------------------------------"
cd "$(dirname "$0")"
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
else
  DOCKER_COMPOSE_CMD=""
fi

if [ -n "$DOCKER_COMPOSE_CMD" ]; then
  if ! $DOCKER_COMPOSE_CMD ps &> /dev/null 2>&1; then
    DOCKER_COMPOSE_CMD="sudo $DOCKER_COMPOSE_CMD"
  fi
  echo "Stopping containers..."
  $DOCKER_COMPOSE_CMD stop 2>/dev/null || true
  sleep 2
fi
echo ""

# Remove ALL Docker images except the ones currently in use
echo "3. Removing ALL Unused Docker Images..."
echo "-------------------------------------------"
# Get list of images used by running containers
USED_IMAGES=$($DOCKER_CMD ps --format "{{.Image}}" 2>/dev/null | sort -u || echo "")
echo "Keeping images used by containers..."
echo "Removing all other images..."
$DOCKER_CMD image prune -a -f
echo ""

# Clean Docker logs aggressively
echo "4. Aggressively Cleaning Docker Logs..."
echo "-------------------------------------------"
if [ -d /var/lib/docker/containers ]; then
  LOG_COUNT=$(find /var/lib/docker/containers -name "*.log" -type f 2>/dev/null | wc -l || echo "0")
  echo "Found $LOG_COUNT log files, truncating..."
  $SUDO_CMD find /var/lib/docker/containers -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  echo "✅ Docker logs truncated"
fi
echo ""

# Clean build cache completely
echo "5. Removing ALL Build Cache..."
echo "-------------------------------------------"
$DOCKER_CMD builder prune -a -f
echo ""

# Clean all stopped containers
echo "6. Removing All Stopped Containers..."
echo "-------------------------------------------"
$DOCKER_CMD container prune -f
echo ""

# Clean all volumes (be careful - this removes data!)
echo "7. Removing Unused Volumes..."
echo "-------------------------------------------"
echo "⚠️  This will remove unused volumes (data will be lost)"
$DOCKER_CMD volume prune -f
echo ""

# Clean systemd journal
echo "8. Cleaning Systemd Journal (keep only 3 days)..."
echo "-------------------------------------------"
if command -v journalctl &> /dev/null; then
  $SUDO_CMD journalctl --vacuum-time=3d 2>/dev/null || true
  echo "✅ Journal cleaned"
fi
echo ""

# Clean APT cache
echo "9. Cleaning APT Cache..."
echo "-------------------------------------------"
if command -v apt-get &> /dev/null; then
  $SUDO_CMD apt-get clean 2>/dev/null || true
  $SUDO_CMD apt-get autoclean 2>/dev/null || true
  $SUDO_CMD apt-get autoremove -y 2>/dev/null || true
  echo "✅ APT cache cleaned"
fi
echo ""

# Clean temporary files
echo "10. Cleaning Temporary Files..."
echo "-------------------------------------------"
$SUDO_CMD rm -rf /tmp/* 2>/dev/null || true
$SUDO_CMD rm -rf /var/tmp/* 2>/dev/null || true
echo "✅ Temporary files cleaned"
echo ""

# Clean npm cache
echo "11. Cleaning npm Cache..."
echo "-------------------------------------------"
if command -v npm &> /dev/null; then
  $SUDO_CMD npm cache clean --force 2>/dev/null || true
fi
echo ""

# Final system prune
echo "12. Final Docker System Prune..."
echo "-------------------------------------------"
$DOCKER_CMD system prune -a -f --volumes
echo ""

# Show final usage
echo "=========================================="
echo "Final Disk Usage"
echo "=========================================="
df -h /
echo ""

AVAILABLE=$(df -h / | tail -1 | awk '{print $4}')
echo "✅ Emergency cleanup complete!"
echo "   Available space: $AVAILABLE"
echo ""

