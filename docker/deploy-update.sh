#!/bin/bash
# Script to deploy updates on EC2 - pulls latest code and force recreates containers

set -e  # Exit on error

echo "=== Jambonz Deployment Script ==="
echo "This script will:"
echo "  1. Pull latest code from git"
echo "  2. Pull latest Docker images"
echo "  3. Force recreate all containers with new configuration"
echo "  4. Verify services are running"
echo ""

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$SCRIPT_DIR"

# Check if we're in the right directory
if [ ! -f "docker-compose.yaml" ]; then
    echo "ERROR: docker-compose.yaml not found. Please run this script from the docker directory."
    exit 1
fi

# Check if HOST_IP is set
if [ -z "$HOST_IP" ]; then
    # Try to get from .env file
    if [ -f ".env" ]; then
        source .env
    fi
    
    # If still not set, try to auto-detect (AWS EC2)
    if [ -z "$HOST_IP" ]; then
        echo "HOST_IP not set. Attempting to auto-detect from EC2 metadata..."
        HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
        
        if [ -z "$HOST_IP" ]; then
            echo "ERROR: HOST_IP environment variable is not set and could not be auto-detected."
            echo "Please set it manually:"
            echo "  export HOST_IP=your-ec2-public-ip"
            echo "  Or create .env file with: HOST_IP=your-ec2-public-ip"
            exit 1
        fi
    fi
fi

echo "Using HOST_IP: $HOST_IP"
echo ""

# Step 1: Pull latest code from git (if in a git repository)
if [ -d "../.git" ]; then
    echo "=== Step 1: Pulling latest code from git ==="
    cd ..
    git pull
    cd docker
    echo "✓ Code updated"
    echo ""
else
    echo "=== Step 1: Skipping git pull (not a git repository) ==="
    echo ""
fi

# Step 2: Pull latest Docker images
echo "=== Step 2: Pulling latest Docker images ==="
sudo docker compose pull
echo "✓ Images pulled"
echo ""

# Step 3: Stop existing containers
echo "=== Step 3: Stopping existing containers ==="
sudo docker compose down
echo "✓ Containers stopped"
echo ""

# Step 4: Force recreate containers with new configuration
echo "=== Step 4: Creating containers with new configuration ==="
echo "This will recreate all containers with the latest configuration..."
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate --remove-orphans
echo "✓ Containers recreated"
echo ""

# Step 5: Wait for MySQL to be healthy
echo "=== Step 5: Waiting for MySQL to be healthy ==="
timeout=60
counter=0
while ! sudo docker compose exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; do
    sleep 2
    counter=$((counter + 2))
    if [ $counter -ge $timeout ]; then
        echo "WARNING: MySQL did not become healthy within $timeout seconds"
        echo "Continuing anyway..."
        break
    fi
    echo -n "."
done
echo ""
echo "✓ MySQL is healthy"
echo ""

# Step 6: Verify services are running
echo "=== Step 6: Verifying services ==="
sleep 5
sudo docker compose ps
echo ""

# Step 7: Check key services
echo "=== Step 7: Checking key services ==="
echo ""

# Check MySQL
if sudo docker compose exec -T mysql mysqladmin ping -h 127.0.0.1 --protocol tcp --silent 2>/dev/null; then
    echo "✓ MySQL is running"
else
    echo "✗ MySQL is not responding"
fi

# Check Redis
if sudo docker compose exec -T redis redis-cli ping 2>/dev/null | grep -q "PONG"; then
    echo "✓ Redis is running"
else
    echo "✗ Redis is not responding"
fi

# Check drachtio-sbc
if sudo docker compose ps | grep -q "drachtio-sbc.*Up"; then
    echo "✓ drachtio-sbc is running"
else
    echo "✗ drachtio-sbc is not running"
fi

# Check rtpengine
if sudo docker compose ps | grep -q "rtpengine.*Up"; then
    echo "✓ rtpengine is running"
else
    echo "✗ rtpengine is not running"
fi

# Check API Server
if curl -s http://localhost:3000/health > /dev/null 2>&1; then
    echo "✓ API Server is accessible"
else
    echo "✗ API Server may not be ready (check logs: docker compose logs api-server)"
fi

# Check Webapp
if curl -s http://localhost:3001 > /dev/null 2>&1; then
    echo "✓ Webapp is accessible"
else
    echo "✗ Webapp may not be ready (check logs: docker compose logs webapp)"
fi

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "Services are available at:"
echo "  - Webapp: http://${HOST_IP}:3001"
echo "  - API Server: http://${HOST_IP}:3000"
echo "  - Jaeger UI: http://${HOST_IP}:16686"
echo ""
echo "SIP Signaling IP: ${HOST_IP}:5060"
echo "RTP Media Port Range: 10000-70000"
echo ""
echo "Useful commands:"
echo "  - View logs: sudo docker compose logs -f [service-name]"
echo "  - Check status: sudo docker compose ps"
echo "  - Restart service: sudo docker compose restart [service-name]"
echo ""

