#!/bin/bash
# Simple script to set up .env file - works with sudo

cd /opt/jambonz-infrastructure/docker

# Get LOCAL_IP from hostname (ip-172-31-13-217 -> 172.31.13.217)
LOCAL_IP=$(hostname | sed 's/^ip-//' | sed 's/-/./g')

# Get HOST_IP from AWS metadata or external service
HOST_IP=$(curl -s --max-time 2 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || curl -s --max-time 5 http://ipecho.net/plain 2>/dev/null || echo "13.203.223.245")

# Create .env file
cat > .env << EOF
LOCAL_IP=${LOCAL_IP}
HOST_IP=${HOST_IP}
EOF

echo "✅ Created .env file:"
echo "   LOCAL_IP=${LOCAL_IP}"
echo "   HOST_IP=${HOST_IP}"

