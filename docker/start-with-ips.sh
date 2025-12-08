#!/bin/bash
# Convenience script to start Docker Compose with auto-detected IPs

set -e

cd "$(dirname "$0")"

# Source the get-ips script to get LOCAL_IP and HOST_IP
source ./get-ips.sh

if [ -z "$LOCAL_IP" ] || [ -z "$HOST_IP" ]; then
  echo "ERROR: Could not detect LOCAL_IP or HOST_IP"
  echo "Please set them manually:"
  echo "  export LOCAL_IP=172.31.13.217"
  echo "  export HOST_IP=13.203.223.245"
  exit 1
fi

echo ""
echo "Starting Docker Compose with:"
echo "  LOCAL_IP=${LOCAL_IP}"
echo "  HOST_IP=${HOST_IP}"
echo ""

# Export for docker compose
export LOCAL_IP
export HOST_IP

# Start docker compose
docker compose up -d

echo ""
echo "Services started. Check logs with:"
echo "  docker compose logs drachtio-sbc | grep -i 'local_ip\|host_ip'"

