#!/bin/bash
# Simple script to set up .env file - works with sudo

cd /opt/jambonz-infrastructure/docker

# For Docker containers, LOCAL_IP should be the Docker network IP (172.10.0.10)
# This is the IP assigned to drachtio-sbc in docker-compose.yaml
# The host's private IP (e.g., 172.31.13.217) is NOT available inside containers
LOCAL_IP="172.10.0.10"

# Get HOST_IP from AWS metadata or external service
HOST_IP=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || \
          curl -s --max-time 5 http://ipecho.net/plain 2>/dev/null || \
          curl -s --max-time 5 http://ifconfig.me 2>/dev/null || \
          curl -s --max-time 5 http://icanhazip.com 2>/dev/null || \
          echo "")

# If still empty, prompt or use known value
if [ -z "$HOST_IP" ]; then
  echo "⚠️  Could not auto-detect HOST_IP"
  echo "Using default: 13.203.223.245"
  echo "If this is incorrect, edit .env file manually"
  HOST_IP="13.203.223.245"
fi

# Create .env file
cat > .env << EOF
LOCAL_IP=${LOCAL_IP}
HOST_IP=${HOST_IP}
EOF

echo "✅ Created .env file:"
echo "   LOCAL_IP=${LOCAL_IP} (Docker network IP for drachtio-sbc)"
echo "   HOST_IP=${HOST_IP} (Public IP for external SIP signaling)"

