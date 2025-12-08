#!/bin/bash
# Script to set up .env file with LOCAL_IP and HOST_IP
# Works with or without sudo

set -e

cd "$(dirname "$0")"

# Get IPs by running get-ips.sh and capturing output
# This works better with sudo since we're not relying on exported variables
IP_OUTPUT=$(bash ./get-ips.sh 2>/dev/null || true)

# Extract LOCAL_IP and HOST_IP from output
LOCAL_IP=$(echo "$IP_OUTPUT" | grep "^LOCAL_IP=" | cut -d'=' -f2 | tr -d '\n')
HOST_IP=$(echo "$IP_OUTPUT" | grep "^HOST_IP=" | cut -d'=' -f2 | tr -d '\n')

# If still empty, try direct detection
if [ -z "$LOCAL_IP" ]; then
  # Try AWS metadata
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/local-ipv4 > /dev/null 2>&1; then
    LOCAL_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
  # Extract from hostname
  elif HOSTNAME=$(hostname 2>/dev/null) && echo "$HOSTNAME" | grep -q "^ip-"; then
    LOCAL_IP=$(echo "$HOSTNAME" | sed 's/^ip-//' | sed 's/-/./g')
  # Get from hostname -I
  elif HOSTNAME_IP=$(hostname -I 2>/dev/null | awk '{print $1}') && [ -n "$HOSTNAME_IP" ]; then
    LOCAL_IP="$HOSTNAME_IP"
  fi
fi

if [ -z "$HOST_IP" ]; then
  # Try AWS metadata
  if curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 > /dev/null 2>&1; then
    HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
  # Try external service
  else
    HOST_IP=$(curl -s --max-time 5 http://ipecho.net/plain 2>/dev/null || curl -s --max-time 5 http://ifconfig.me 2>/dev/null || curl -s --max-time 5 http://icanhazip.com 2>/dev/null || echo "")
  fi
fi

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

