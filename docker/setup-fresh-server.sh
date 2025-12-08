#!/bin/bash

# Jambonz Fresh Server Setup Script
# This script sets up Jambonz on a completely fresh server with nothing pre-installed

set -e

echo "=========================================="
echo "Jambonz Fresh Server Setup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
    OS=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    VER=$(lsb_release -sr)
else
    echo -e "${RED}ERROR: Cannot detect OS${NC}"
    exit 1
fi

echo -e "${BLUE}Detected OS: $OS $VER${NC}"
echo ""

# Get public IP from AWS metadata
echo "Detecting public IP address..."
PUBLIC_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
if [ -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}WARNING: Could not detect public IP from metadata${NC}"
    read -p "Please enter your public IP address: " PUBLIC_IP
    if [ -z "$PUBLIC_IP" ]; then
        echo -e "${RED}ERROR: Public IP is required${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"
echo ""

# Step 1: Update system and install prerequisites
echo "=========================================="
echo "Step 1: Updating System and Installing Prerequisites"
echo "=========================================="

if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
    echo "Updating package lists..."
    sudo apt-get update
    echo "Installing prerequisites..."
    sudo apt-get install -y ca-certificates curl gnupg lsb-release wget git
elif [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
    echo "Installing prerequisites..."
    sudo yum update -y
    sudo yum install -y ca-certificates curl wget git
else
    echo -e "${RED}ERROR: Unsupported OS: $OS${NC}"
    exit 1
fi

echo -e "${GREEN}Prerequisites installed${NC}"
echo ""

# Step 2: Install Docker
echo "=========================================="
echo "Step 2: Installing Docker"
echo "=========================================="

if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker is already installed${NC}"
    docker --version
else
    echo "Installing Docker..."
    
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        # Add Docker's official GPG key
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/${OS}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        
        # Set up repository
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${OS} $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        # Install Docker
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        
    elif [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
        sudo yum install -y docker
        sudo systemctl enable docker
        sudo systemctl start docker
    fi
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    echo -e "${GREEN}Docker installed successfully${NC}"
fi

# Start Docker service
sudo systemctl start docker 2>/dev/null || true
sudo systemctl enable docker 2>/dev/null || true

# Apply docker group (may require new session, but try to use it)
if ! groups | grep -q docker; then
    echo -e "${YELLOW}Note: You may need to logout and login again for docker group to take effect${NC}"
    echo -e "${YELLOW}Or run: newgrp docker${NC}"
    # Try to use docker with sudo for now
    DOCKER_CMD="sudo docker"
    DOCKER_COMPOSE_CMD="sudo docker compose"
else
    DOCKER_CMD="docker"
    DOCKER_COMPOSE_CMD="docker compose"
fi

# Verify Docker
echo "Verifying Docker installation..."
$DOCKER_CMD --version
$DOCKER_COMPOSE_CMD version || echo -e "${YELLOW}Docker Compose plugin may need a moment to be available${NC}"

echo ""

# Step 3: Install Git (if not present)
echo "=========================================="
echo "Step 3: Checking Git"
echo "=========================================="

if ! command -v git &> /dev/null; then
    echo "Git is already installed from prerequisites"
else
    git --version
fi
echo ""

# Step 4: Clone Repository
echo "=========================================="
echo "Step 4: Setting up Jambonz Infrastructure"
echo "=========================================="

INSTALL_DIR="/opt/jambonz-infrastructure"
echo "Installation directory: $INSTALL_DIR"

if [ -d "$INSTALL_DIR" ]; then
    echo -e "${YELLOW}Directory $INSTALL_DIR already exists${NC}"
    read -p "Do you want to remove it and start fresh? (y/n): " REMOVE_DIR
    if [[ "$REMOVE_DIR" == "y" ]]; then
        echo "Removing existing directory..."
        sudo rm -rf "$INSTALL_DIR"
    else
        echo "Updating existing repository..."
        cd "$INSTALL_DIR"
        sudo git pull || echo -e "${YELLOW}Could not pull updates${NC}"
        sudo git submodule update --init --recursive || echo -e "${YELLOW}Could not update submodules${NC}"
        cd "$INSTALL_DIR/docker"
    fi
fi

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Cloning jambonz-infrastructure repository..."
    sudo mkdir -p "$(dirname $INSTALL_DIR)"
    cd "$(dirname $INSTALL_DIR)"
    sudo git clone https://github.com/rishabh171998/jambonz-infrastructure.git "$(basename $INSTALL_DIR)" || {
        echo -e "${RED}ERROR: Failed to clone repository${NC}"
        exit 1
    }
    
    echo "Initializing git submodules..."
    cd "$INSTALL_DIR"
    sudo git submodule update --init --recursive || {
        echo -e "${YELLOW}WARNING: Some submodules may have failed to initialize${NC}"
    }
    
    # Change ownership
    sudo chown -R $USER:$USER "$INSTALL_DIR"
fi

cd "$INSTALL_DIR/docker"
echo -e "${GREEN}Repository setup complete${NC}"
echo ""

# Step 5: Set up .env file
echo "=========================================="
echo "Step 5: Configuring Environment"
echo "=========================================="

if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env << EOF
HOST_IP=$PUBLIC_IP
EOF
    echo -e "${GREEN}.env file created with HOST_IP=$PUBLIC_IP${NC}"
else
    echo ".env file already exists"
    if grep -q "HOST_IP" .env; then
        echo "Updating HOST_IP in .env file..."
        sed -i "s/^HOST_IP=.*/HOST_IP=$PUBLIC_IP/" .env || {
            echo "HOST_IP=$PUBLIC_IP" >> .env
        }
    else
        echo "HOST_IP=$PUBLIC_IP" >> .env
    fi
    echo -e "${GREEN}Updated .env file with HOST_IP=$PUBLIC_IP${NC}"
fi

echo ""

# Step 6: Authenticate with GHCR (if needed)
echo "=========================================="
echo "Step 6: GitHub Container Registry Authentication"
echo "=========================================="

echo "Checking if GHCR authentication is needed..."
if [ -f "ghcr-auth.sh" ]; then
    echo -e "${YELLOW}If you need to pull private images from GHCR, run:${NC}"
    echo "  export GHCR_USER=your-username"
    echo "  export GHCR_PAT=your-personal-access-token"
    echo "  ./ghcr-auth.sh"
    echo ""
    echo "Skipping for now (assuming public images)..."
else
    echo "GHCR auth script not found, skipping..."
fi
echo ""

# Step 7: Start Docker Compose services
echo "=========================================="
echo "Step 7: Starting Docker Compose Services"
echo "=========================================="

echo "This will take several minutes on first run..."
echo ""

# Use sudo if needed
if groups | grep -q docker; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="sudo docker compose"
fi

# Pull images first
echo "Pulling Docker images..."
$COMPOSE_CMD pull || echo -e "${YELLOW}Some images may not be available yet${NC}"

# Start services
echo "Starting services..."
$COMPOSE_CMD up -d || {
    echo -e "${RED}ERROR: Failed to start Docker Compose services${NC}"
    echo "Checking logs..."
    $COMPOSE_CMD logs --tail=50
    exit 1
}

echo -e "${GREEN}Docker Compose services started${NC}"
echo ""

# Wait for services to be ready
echo "Waiting for services to initialize (this may take 2-3 minutes)..."
sleep 30

# Check service status
echo "Checking service status..."
$COMPOSE_CMD ps

echo ""
echo -e "${YELLOW}Services are starting. Please wait 2-3 minutes for all services to be fully ready.${NC}"
echo ""

# Step 8: Update SBC IP addresses
echo "=========================================="
echo "Step 8: Updating SBC IP Addresses"
echo "=========================================="

if [ -f "update-sbc-ip.sh" ]; then
    chmod +x update-sbc-ip.sh
    echo "Updating SBC IP addresses in database..."
    sleep 60  # Wait a bit more for MySQL to be ready
    ./update-sbc-ip.sh || {
        echo -e "${YELLOW}WARNING: Failed to update SBC IP addresses. You can run this manually later:${NC}"
        echo "  ./update-sbc-ip.sh"
    }
else
    echo -e "${YELLOW}update-sbc-ip.sh not found. You'll need to update SBC IPs manually.${NC}"
fi

echo ""

# Final summary
echo "=========================================="
echo -e "${GREEN}Setup Complete!${NC}"
echo "=========================================="
echo ""
echo -e "${GREEN}Jambonz is now running on your server!${NC}"
echo ""
echo "Access URLs:"
echo "  - Webapp: http://$PUBLIC_IP:3001"
echo "  - API: http://$PUBLIC_IP:3000"
echo ""
echo "Default credentials:"
echo "  - Username: admin"
echo "  - Password: admin (you'll be forced to change it)"
echo ""
echo "SIP Signaling IP (for carriers to whitelist):"
echo "  - $PUBLIC_IP:5060"
echo ""
echo -e "${YELLOW}Important Next Steps:${NC}"
echo "  1. Configure AWS Security Group (if not done already)"
echo "     - Allow UDP/TCP 5060 (SIP)"
echo "     - Allow UDP 40000-60000 (RTP)"
echo "     - Allow TCP 3000 (API) and 3001 (Webapp)"
echo ""
echo "  2. Wait 2-3 minutes for all services to fully start"
echo "     Check status: cd $INSTALL_DIR/docker && $COMPOSE_CMD ps"
echo ""
echo "  3. Log into webapp and change default password"
echo ""
echo "  4. Create account and set SIP realm domain (account level)"
echo ""
echo "  5. Add TTS/STT credentials (GCP or AWS) if needed"
echo ""
echo "Useful commands:"
echo "  - View logs: cd $INSTALL_DIR/docker && $COMPOSE_CMD logs -f"
echo "  - Stop services: cd $INSTALL_DIR/docker && $COMPOSE_CMD down"
echo "  - Start services: cd $INSTALL_DIR/docker && $COMPOSE_CMD up -d"
echo "  - Restart services: cd $INSTALL_DIR/docker && $COMPOSE_CMD restart"
echo "  - Update SBC IP: cd $INSTALL_DIR/docker && ./update-sbc-ip.sh"
echo ""
echo -e "${YELLOW}Note:${NC}"
echo "  - SIP Realm: Set per account in webapp (e.g., sip.yourcompany.com)"
echo "  - SIP Signaling IP: Already configured ($PUBLIC_IP:5060)"
echo "  - These are different: SIP Realm = device registration, SIP IP = carrier traffic"
echo ""
echo "=========================================="

