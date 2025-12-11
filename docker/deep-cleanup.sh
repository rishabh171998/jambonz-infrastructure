#!/bin/bash
# Deep cleanup - finds and removes large files and caches

set -e

echo "=========================================="
echo "Deep System Cleanup"
echo "=========================================="
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
echo "-------------------------------------------"
df -h /
echo ""

# Clean Docker logs
echo "2. Cleaning Docker Container Logs..."
echo "-------------------------------------------"
if [ -d /var/lib/docker/containers ]; then
  LOG_SIZE_BEFORE=$(du -sh /var/lib/docker/containers 2>/dev/null | awk '{print $1}' || echo "0")
  echo "Docker logs size before: $LOG_SIZE_BEFORE"
  
  # Truncate all log files (keeps containers running but clears logs)
  $SUDO_CMD find /var/lib/docker/containers -name "*.log" -type f -exec truncate -s 0 {} \; 2>/dev/null || true
  
  LOG_SIZE_AFTER=$(du -sh /var/lib/docker/containers 2>/dev/null | awk '{print $1}' || echo "0")
  echo "✅ Docker logs cleaned"
  echo "   Size after: $LOG_SIZE_AFTER"
else
  echo "⚠️  Docker logs directory not found"
fi
echo ""

# Clean system logs
echo "3. Cleaning System Logs..."
echo "-------------------------------------------"
if [ -d /var/log ]; then
  # Remove old log files (older than 7 days)
  OLD_LOGS=$($SUDO_CMD find /var/log -type f -name "*.log" -mtime +7 2>/dev/null | wc -l || echo "0")
  if [ "$OLD_LOGS" -gt 0 ]; then
    echo "Found $OLD_LOGS old log files, removing..."
    $SUDO_CMD find /var/log -type f -name "*.log" -mtime +7 -delete 2>/dev/null || true
    echo "✅ Old system logs removed"
  else
    echo "✅ No old system logs to remove"
  fi
  
  # Clean journal logs (systemd)
  if command -v journalctl &> /dev/null; then
    JOURNAL_SIZE_BEFORE=$($SUDO_CMD journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' || echo "0")
    echo "Journal size before: $JOURNAL_SIZE_BEFORE"
    $SUDO_CMD journalctl --vacuum-time=7d 2>/dev/null || true
    JOURNAL_SIZE_AFTER=$($SUDO_CMD journalctl --disk-usage 2>/dev/null | grep -oP '\d+\.\d+\w+' || echo "0")
    echo "✅ Journal logs cleaned"
    echo "   Size after: $JOURNAL_SIZE_AFTER"
  fi
fi
echo ""

# Clean apt cache (if on Debian/Ubuntu)
echo "4. Cleaning Package Cache..."
echo "-------------------------------------------"
if command -v apt-get &> /dev/null; then
  APT_SIZE_BEFORE=$($SUDO_CMD du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "0")
  echo "APT cache size before: $APT_SIZE_BEFORE"
  $SUDO_CMD apt-get clean 2>/dev/null || true
  $SUDO_CMD apt-get autoclean 2>/dev/null || true
  APT_SIZE_AFTER=$($SUDO_CMD du -sh /var/cache/apt/archives 2>/dev/null | awk '{print $1}' || echo "0")
  echo "✅ APT cache cleaned"
  echo "   Size after: $APT_SIZE_AFTER"
else
  echo "⚠️  APT not found (not Debian/Ubuntu)"
fi
echo ""

# Clean temporary files
echo "5. Cleaning Temporary Files..."
echo "-------------------------------------------"
# /tmp
if [ -d /tmp ]; then
  TMP_SIZE_BEFORE=$(du -sh /tmp 2>/dev/null | awk '{print $1}' || echo "0")
  echo "Temp files size before: $TMP_SIZE_BEFORE"
  $SUDO_CMD find /tmp -type f -atime +7 -delete 2>/dev/null || true
  TMP_SIZE_AFTER=$(du -sh /tmp 2>/dev/null | awk '{print $1}' || echo "0")
  echo "✅ Temporary files cleaned"
  echo "   Size after: $TMP_SIZE_AFTER"
fi

# /var/tmp
if [ -d /var/tmp ]; then
  VARTMP_SIZE_BEFORE=$(du -sh /var/tmp 2>/dev/null | awk '{print $1}' || echo "0")
  echo "Var temp files size before: $VARTMP_SIZE_BEFORE"
  $SUDO_CMD find /var/tmp -type f -atime +7 -delete 2>/dev/null || true
  VARTMP_SIZE_AFTER=$(du -sh /var/tmp 2>/dev/null | awk '{print $1}' || echo "0")
  echo "✅ Var temporary files cleaned"
  echo "   Size after: $VARTMP_SIZE_AFTER"
fi
echo ""

# Find and report large files
echo "6. Finding Large Files (>100MB)..."
echo "-------------------------------------------"
echo "Top 10 largest files/directories:"
$SUDO_CMD du -h --max-depth=1 / 2>/dev/null | sort -rh | head -10 || echo "Cannot check (permission denied)"
echo ""

# Clean npm cache (if exists)
echo "7. Cleaning npm Cache..."
echo "-------------------------------------------"
if command -v npm &> /dev/null; then
  NPM_CACHE=$($SUDO_CMD npm config get cache 2>/dev/null || echo "")
  if [ -n "$NPM_CACHE" ] && [ -d "$NPM_CACHE" ]; then
    NPM_SIZE_BEFORE=$(du -sh "$NPM_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
    echo "npm cache size before: $NPM_SIZE_BEFORE"
    $SUDO_CMD npm cache clean --force 2>/dev/null || true
    NPM_SIZE_AFTER=$(du -sh "$NPM_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
    echo "✅ npm cache cleaned"
    echo "   Size after: $NPM_SIZE_AFTER"
  else
    echo "⚠️  npm cache not found"
  fi
else
  echo "⚠️  npm not found"
fi
echo ""

# Clean Docker buildx cache (if exists)
echo "8. Cleaning Docker Buildx Cache..."
echo "-------------------------------------------"
if [ -d ~/.docker/buildx ] || [ -d /root/.docker/buildx ]; then
  BUILDX_CACHE=$(find ~/.docker/buildx /root/.docker/buildx -type d -name "cache" 2>/dev/null | head -1)
  if [ -n "$BUILDX_CACHE" ]; then
    BUILDX_SIZE_BEFORE=$(du -sh "$BUILDX_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
    echo "Buildx cache size before: $BUILDX_SIZE_BEFORE"
    $SUDO_CMD rm -rf "$BUILDX_CACHE"/* 2>/dev/null || true
    BUILDX_SIZE_AFTER=$(du -sh "$BUILDX_CACHE" 2>/dev/null | awk '{print $1}' || echo "0")
    echo "✅ Buildx cache cleaned"
    echo "   Size after: $BUILDX_SIZE_AFTER"
  else
    echo "✅ No buildx cache found"
  fi
else
  echo "✅ No buildx cache directory"
fi
echo ""

# Final Docker system prune (just to be sure)
echo "9. Final Docker System Prune..."
echo "-------------------------------------------"
$DOCKER_CMD system prune -f
echo "✅ Final Docker cleanup done"
echo ""

# Show final usage
echo "=========================================="
echo "Final Disk Usage"
echo "=========================================="
df -h /
echo ""

# Calculate space freed
echo "=========================================="
echo "Cleanup Complete!"
echo "=========================================="
echo ""
echo "✅ Deep cleanup completed"
echo ""
echo "If you need more space, check:"
echo "  1. Large files: sudo du -h --max-depth=1 / | sort -rh | head -20"
echo "  2. Docker images: sudo docker images"
echo "  3. Old backups or data files"
echo ""

