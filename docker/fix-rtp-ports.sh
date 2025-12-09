#!/bin/bash
# Script to fix RTP port configuration issues

set -e

echo "=== Fixing RTP Port Configuration ==="
cd "$(dirname "$0")"

# Check HOST_IP
if [ -z "$HOST_IP" ]; then
    if [ -f ".env" ]; then
        source .env
    fi
    if [ -z "$HOST_IP" ]; then
        HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
        if [ -z "$HOST_IP" ]; then
            echo "ERROR: HOST_IP not set"
            exit 1
        fi
    fi
fi

echo "Using HOST_IP: $HOST_IP"
echo ""

# Option 1: Try bridge networking with port range (may fail if Docker doesn't support it)
echo "Attempting to use bridge networking with port range 10000-70000..."
echo "If this fails, we'll use host networking instead."
echo ""

# Stop rtpengine
sudo docker compose stop rtpengine 2>/dev/null || true

# Try to start with bridge networking
if sudo HOST_IP="$HOST_IP" docker compose up -d rtpengine 2>&1 | grep -q "invalid containerPort\|port range"; then
    echo "Docker Compose doesn't support large port range, using host networking..."
    
    # Update docker-compose.yaml to use host networking
    # This is a temporary fix - you may need to edit manually
    echo ""
    echo "Please update docker-compose.yaml rtpengine section to:"
    echo ""
    echo "  rtpengine:"
    echo "    image: drachtio/rtpengine:jambonz-test"
    echo "    restart: always"
    echo "    network_mode: host"
    echo "    command: [\"rtpengine\", \"--interface\", \"private/127.0.0.1\", \"--interface\", \"public/0.0.0.0!\${HOST_IP}\", \"--listen-ng\", \"127.0.0.1:22222\", \"--port-min\", \"10000\", \"--port-max\", \"70000\", \"--log-level\", \"5\"]"
    echo ""
    echo "And update JAMBONES_RTPENGINES to '172.10.0.1:22222' in sbc-inbound and sbc-outbound"
    echo ""
    echo "Then run: sudo HOST_IP=\"$HOST_IP\" docker compose up -d --force-recreate rtpengine"
else
    echo "✓ rtpengine started with bridge networking"
    echo ""
    echo "Verifying rtpengine..."
    sleep 3
    if sudo docker compose ps | grep -q "rtpengine.*Up"; then
        echo "✓ rtpengine is running"
        sudo docker compose logs rtpengine --tail 10 | grep -i "port\|listening" || true
    else
        echo "✗ rtpengine failed to start, check logs:"
        sudo docker compose logs rtpengine --tail 20
    fi
fi

echo ""
echo "=== Next Steps ==="
echo "1. Check rtpengine logs: sudo docker compose logs rtpengine"
echo "2. Verify security group allows UDP 10000-70000"
echo "3. Test RTP connectivity from external network"
echo "4. Check other services can reach rtpengine: sudo docker compose exec sbc-inbound nc -zv rtpengine 22222"

