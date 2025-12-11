#!/bin/bash
# Find large files and directories to help identify what's taking up space

set -e

echo "=========================================="
echo "Find Large Files"
echo "=========================================="
echo ""

# Check if we need sudo
if ! docker ps &> /dev/null 2>&1; then
  SUDO_CMD="sudo"
else
  SUDO_CMD=""
fi

# Top 20 largest directories
echo "1. Top 20 Largest Directories..."
echo "-------------------------------------------"
$SUDO_CMD du -h --max-depth=1 / 2>/dev/null | sort -rh | head -20 || echo "Cannot check (permission denied)"
echo ""

# Top 20 largest files
echo "2. Top 20 Largest Files..."
echo "-------------------------------------------"
$SUDO_CMD find / -type f -size +100M 2>/dev/null | head -20 | while read file; do
  size=$($SUDO_CMD du -h "$file" 2>/dev/null | awk '{print $1}')
  echo "$size - $file"
done || echo "Cannot check (permission denied)"
echo ""

# Docker specific
echo "3. Docker Disk Usage Breakdown..."
echo "-------------------------------------------"
if command -v docker &> /dev/null; then
  if ! docker ps &> /dev/null 2>&1; then
    DOCKER_CMD="sudo docker"
  else
    DOCKER_CMD="docker"
  fi
  
  echo "Images:"
  $DOCKER_CMD images --format "{{.Repository}}:{{.Tag}}\t{{.Size}}" | sort -k2 -h | tail -10
  echo ""
  
  echo "Volumes:"
  $DOCKER_CMD volume ls --format "{{.Name}}" | while read vol; do
    size=$($DOCKER_CMD system df -v 2>/dev/null | grep "$vol" | awk '{print $3}' || echo "unknown")
    echo "  $vol: $size"
  done
  echo ""
  
  echo "Container sizes:"
  $DOCKER_CMD ps -a --format "{{.Names}}\t{{.Size}}" | sort -k2 -h | tail -10
else
  echo "Docker not found"
fi
echo ""

# Check specific common large directories
echo "4. Common Large Directories..."
echo "-------------------------------------------"
for dir in /var/lib/docker /var/log /tmp /var/tmp /usr /opt /home; do
  if [ -d "$dir" ]; then
    size=$($SUDO_CMD du -sh "$dir" 2>/dev/null | awk '{print $1}' || echo "unknown")
    echo "$dir: $size"
  fi
done
echo ""

# Docker logs specifically
echo "5. Docker Logs Size..."
echo "-------------------------------------------"
if [ -d /var/lib/docker/containers ]; then
  LOG_SIZE=$($SUDO_CMD du -sh /var/lib/docker/containers 2>/dev/null | awk '{print $1}' || echo "0")
  echo "Docker container logs: $LOG_SIZE"
  
  # Show largest log files
  echo "Largest log files:"
  $SUDO_CMD find /var/lib/docker/containers -name "*.log" -type f -exec du -h {} \; 2>/dev/null | sort -rh | head -5 || echo "Cannot check"
else
  echo "Docker logs directory not found"
fi
echo ""

echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""
echo "To clean up specific items:"
echo "  - Docker logs: sudo truncate -s 0 /var/lib/docker/containers/*/*.log"
echo "  - System logs: sudo journalctl --vacuum-time=7d"
echo "  - APT cache: sudo apt-get clean"
echo "  - Docker images: sudo docker image prune -a"
echo ""

