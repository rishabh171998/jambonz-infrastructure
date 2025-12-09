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

# For Docker deployments, LOCAL_IP must be the Docker network IP (172.10.0.10)
# This is the IP assigned to drachtio-sbc in docker-compose.yaml
# The host's private IP (e.g., 172.31.13.217) is NOT available inside containers
# and will cause "Cannot assign requested address" errors
LOCAL_IP="172.10.0.10"

if [ -z "$HOST_IP" ]; then
  echo "Attempting to detect HOST_IP..."
  
  # Try AWS metadata service first (returns Elastic IP if associated, otherwise public IP)
  AWS_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
  
  if [ -n "$AWS_IP" ] && [[ "$AWS_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    HOST_IP="$AWS_IP"
    echo "  ✓ Detected from AWS metadata: $HOST_IP"
  else
    # Try external services as fallback
    echo "  Trying external services..."
    HOST_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || \
              curl -s --max-time 5 https://ifconfig.me 2>/dev/null || \
              curl -s --max-time 5 http://icanhazip.com 2>/dev/null || \
              curl -s --max-time 5 http://ipecho.net/plain 2>/dev/null || \
              echo "")
    
    if [ -n "$HOST_IP" ] && [[ "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
      echo "  ✓ Detected from external service: $HOST_IP"
    fi
  fi
fi

# LOCAL_IP is always set to Docker network IP above, so this check should never fail
# But keeping it for safety
if [ -z "$LOCAL_IP" ]; then
  echo "ERROR: LOCAL_IP is not set (this should not happen)"
  echo "For Docker, LOCAL_IP should be 172.10.0.10"
  exit 1
fi

# If still no HOST_IP, prompt user
if [ -z "$HOST_IP" ] || [[ ! "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo ""
  echo "⚠️  Could not automatically detect HOST_IP"
  echo ""
  echo "Please enter your Elastic IP or public IP address:"
  read -p "HOST_IP: " HOST_IP
  
  # Validate input
  if [ -z "$HOST_IP" ] || [[ ! "$HOST_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ""
    echo "ERROR: Invalid IP address format"
    echo "Please set it manually:"
    echo "  export HOST_IP=your-elastic-ip"
    echo "  ./setup-env.sh"
    exit 1
  fi
fi

echo "Detected IPs:"
echo "  LOCAL_IP=${LOCAL_IP}"
echo "  HOST_IP=${HOST_IP}"
echo ""

# Create or update .env file (handle permissions)
ENV_FILE=".env"
TEMP_FILE=$(mktemp .env.XXXXXX 2>/dev/null || echo ".env.tmp.$$")

# Create temp file with new values
if [ -f "$ENV_FILE" ]; then
  # Copy existing file, remove old LOCAL_IP and HOST_IP lines
  grep -v "^LOCAL_IP=" "$ENV_FILE" 2>/dev/null | grep -v "^HOST_IP=" > "$TEMP_FILE" 2>/dev/null || true
else
  # Create empty temp file
  > "$TEMP_FILE"
fi

# Append the IPs to temp file
{
  echo "LOCAL_IP=${LOCAL_IP}"
  echo "HOST_IP=${HOST_IP}"
} >> "$TEMP_FILE"

# Check if .env file exists and if we have write permissions
if [ -f "$ENV_FILE" ] && [ ! -w "$ENV_FILE" ]; then
  echo "⚠️  .env file is not writable. Trying with sudo..."
  # Use sudo to move the file
  sudo mv "$TEMP_FILE" "$ENV_FILE" 2>/dev/null || {
    echo "ERROR: Could not write to .env file (permission denied)"
    echo "Please run with sudo or fix permissions:"
    echo "  sudo chown \$USER:\$USER .env"
    rm -f "$TEMP_FILE" 2>/dev/null
    exit 1
  }
  sudo chmod 644 "$ENV_FILE" 2>/dev/null || true
  sudo chown "$USER:$USER" "$ENV_FILE" 2>/dev/null || true
else
  # Normal move (handles permissions)
  mv "$TEMP_FILE" "$ENV_FILE" 2>/dev/null || {
    echo "ERROR: Could not write to .env file"
    rm -f "$TEMP_FILE" 2>/dev/null
    exit 1
  }
  chmod 644 "$ENV_FILE" 2>/dev/null || true
fi

echo "✅ Updated .env file with:"
echo "   LOCAL_IP=${LOCAL_IP}"
echo "   HOST_IP=${HOST_IP}"
echo ""
echo "You can now start Docker Compose:"
echo "   docker compose up -d"

