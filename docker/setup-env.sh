#!/bin/bash
# Script to set up .env file with LOCAL_IP and HOST_IP
# Works with or without sudo

set -e

cd "$(dirname "$0")"

# Source get-ips.sh to detect IPs
source ./get-ips.sh

if [ -z "$LOCAL_IP" ]; then
  echo "ERROR: Could not detect LOCAL_IP"
  echo "Please set it manually:"
  echo "  export LOCAL_IP=172.31.13.217"
  exit 1
fi

if [ -z "$HOST_IP" ]; then
  echo "ERROR: Could not detect HOST_IP"
  echo "Please set it manually:"
  echo "  export HOST_IP=13.203.223.245"
  exit 1
fi

echo "Detected IPs:"
echo "  LOCAL_IP=${LOCAL_IP}"
echo "  HOST_IP=${HOST_IP}"
echo ""

# Create or update .env file (handle permissions)
ENV_FILE=".env"
TEMP_FILE=".env.tmp"

# Create temp file with new values
if [ -f "$ENV_FILE" ]; then
  # Copy existing file, remove old LOCAL_IP and HOST_IP lines
  grep -v "^LOCAL_IP=" "$ENV_FILE" | grep -v "^HOST_IP=" > "$TEMP_FILE" 2>/dev/null || true
else
  touch "$TEMP_FILE"
fi

# Append the IPs
echo "LOCAL_IP=${LOCAL_IP}" >> "$TEMP_FILE"
echo "HOST_IP=${HOST_IP}" >> "$TEMP_FILE"

# Move temp file to .env (this handles permissions)
mv "$TEMP_FILE" "$ENV_FILE"

# Fix permissions if needed
chmod 644 "$ENV_FILE" 2>/dev/null || true

echo "✅ Updated .env file with:"
echo "   LOCAL_IP=${LOCAL_IP}"
echo "   HOST_IP=${HOST_IP}"
echo ""
echo "You can now start Docker Compose:"
echo "   docker compose up -d"

