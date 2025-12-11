#!/bin/bash
# Monitor disk space during build and alert if getting low

set -e

echo "Monitoring disk space..."
echo "Press Ctrl+C to stop"
echo ""

while true; do
  clear
  echo "=========================================="
  echo "Disk Space Monitor"
  echo "=========================================="
  echo ""
  df -h /
  echo ""
  
  # Check if we need sudo
  if ! docker ps &> /dev/null 2>&1; then
    DOCKER_CMD="sudo docker"
  else
    DOCKER_CMD="docker"
  fi
  
  echo "Docker Disk Usage:"
  $DOCKER_CMD system df
  echo ""
  
  AVAILABLE=$(df / | tail -1 | awk '{print $4}' | sed 's/[^0-9]//g')
  if [ "$AVAILABLE" -lt 1000000 ]; then  # Less than 1GB
    echo "⚠️  WARNING: Less than 1GB available!"
    echo "   Run cleanup: sudo docker system prune -a -f"
  fi
  
  sleep 5
done

