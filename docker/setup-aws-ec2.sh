#!/bin/bash

# Jambonz Docker Setup Script for AWS EC2
# This script sets up Jambonz on an AWS EC2 instance

set -e

echo "=========================================="
echo "Jambonz Docker Setup for AWS EC2"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

echo "Detected OS: $OS $VER"
echo ""

# Get public IP from AWS metadata
echo "Detecting public IP address..."
PUBLIC_IP=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4)
if [ -z "$PUBLIC_IP" ]; then
    echo -e "${YELLOW}WARNING: Could not detect public IP from metadata${NC}"
    read -p "Please enter your public IP address: " PUBLIC_IP
fi

echo -e "${GREEN}Public IP: $PUBLIC_IP${NC}"
echo ""

# Step 1: Install Docker
echo "=========================================="
echo "Step 1: Installing Docker"
echo "=========================================="

if command -v docker &> /dev/null; then
    echo -e "${GREEN}Docker is already installed${NC}"
    docker --version
else
    echo "Installing Docker..."
    
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        sudo apt-get update
        sudo apt-get install -y ca-certificates curl gnupg lsb-release
        
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
    else
        echo -e "${RED}ERROR: Unsupported OS: $OS${NC}"
        exit 1
    fi
    
    # Add current user to docker group
    sudo usermod -aG docker $USER
    echo -e "${GREEN}Docker installed successfully${NC}"
fi

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Verify Docker
docker --version
docker compose version

echo ""

# Step 2: Install Git (if not present)
echo "=========================================="
echo "Step 2: Checking Git"
echo "=========================================="

if ! command -v git &> /dev/null; then
    echo "Installing Git..."
    if [[ "$OS" == "ubuntu" ]] || [[ "$OS" == "debian" ]]; then
        sudo apt-get install -y git
    elif [[ "$OS" == "amzn" ]] || [[ "$OS" == "rhel" ]] || [[ "$OS" == "centos" ]]; then
        sudo yum install -y git
    fi
fi

git --version
echo ""

# Step 3: Clone Repository
echo "=========================================="
echo "Step 3: Setting up Jambonz Infrastructure"
echo "=========================================="

INSTALL_DIR="${INSTALL_DIR:-/opt/jambonz}"
echo "Installation directory: $INSTALL_DIR"

if [ ! -d "$INSTALL_DIR" ]; then
    echo "Cloning jambonz-infrastructure repository..."
    sudo mkdir -p "$INSTALL_DIR"
    sudo chown $USER:$USER "$INSTALL_DIR"
    
    cd "$INSTALL_DIR"
    git clone https://github.com/jambonz/jambonz-infrastructure.git .
    
    echo "Initializing git submodules..."
    git submodule update --init --recursive
else
    echo -e "${YELLOW}Directory $INSTALL_DIR already exists${NC}"
    read -p "Do you want to update it? (y/n): " UPDATE_REPO
    if [[ "$UPDATE_REPO" == "y" ]]; then
        cd "$INSTALL_DIR"
        git pull
        git submodule update --init --recursive
    fi
fi

cd "$INSTALL_DIR/docker"
echo ""

# Step 4: Set up .env file
echo "=========================================="
echo "Step 4: Configuring Environment"
echo "=========================================="

if [ ! -f .env ]; then
    echo "Creating .env file..."
    cat > .env <<EOF
# Jambonz Docker Configuration for AWS EC2
# Public IP address - CRITICAL for AWS deployment
HOST_IP=$PUBLIC_IP

# Database configuration (defaults)
DB_HOST=mysql
DB_PORT=3306
DB_USER=jambones
DB_PASS=jambones
DB_NAME=jambones

# Redis configuration
REDIS_HOST=redis
REDIS_PORT=6379

# Optional: AWS credentials for Polly TTS (if using AWS instead of Google)
# AWS_ACCESS_KEY_ID=your-access-key
# AWS_SECRET_ACCESS_KEY=your-secret-key
# AWS_REGION=us-east-1

# Optional: Google Cloud credentials path (if using Google TTS/STT)
# GCP_CREDENTIALS_PATH=credentials/gcp.json
EOF
    echo -e "${GREEN}.env file created${NC}"
else
    echo -e "${YELLOW}.env file already exists${NC}"
    read -p "Do you want to update HOST_IP? (y/n): " UPDATE_ENV
    if [[ "$UPDATE_ENV" == "y" ]]; then
        # Update HOST_IP in .env file
        if grep -q "^HOST_IP=" .env; then
            sed -i "s|^HOST_IP=.*|HOST_IP=$PUBLIC_IP|" .env
        else
            echo "HOST_IP=$PUBLIC_IP" >> .env
        fi
        echo -e "${GREEN}HOST_IP updated to $PUBLIC_IP${NC}"
    fi
fi

echo ""

# Step 5: Set up credentials directory
echo "=========================================="
echo "Step 5: Setting up Credentials"
echo "=========================================="

mkdir -p credentials
echo "Credentials directory created: $INSTALL_DIR/docker/credentials"
echo ""
echo -e "${YELLOW}IMPORTANT: You need to set up credentials for TTS/STT${NC}"
echo ""
echo "Option 1: Google Cloud (recommended for development)"
echo "  1. Download service account JSON key from GCP Console"
echo "  2. Save it as: credentials/gcp.json"
echo ""
echo "Option 2: AWS Polly (if using AWS)"
echo "  1. Set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY in .env"
echo "  2. Or use IAM role for EC2 instance"
echo ""
read -p "Press Enter to continue (you can add credentials later)..."

echo ""

# Step 6: Authenticate with GHCR (if needed)
echo "=========================================="
echo "Step 6: GitHub Container Registry Authentication"
echo "=========================================="

echo "Do you need to authenticate with GitHub Container Registry (GHCR)?"
echo "This is required if the Docker images are private."
read -p "Authenticate with GHCR? (y/n): " AUTH_GHCR

if [[ "$AUTH_GHCR" == "y" ]]; then
    read -p "Enter your GitHub username: " GHCR_USER
    read -sp "Enter your GitHub Personal Access Token: " GHCR_PAT
    echo ""
    
    if [ -n "$GHCR_USER" ] && [ -n "$GHCR_PAT" ]; then
        echo "$GHCR_PAT" | docker login ghcr.io -u "$GHCR_USER" --password-stdin
        echo -e "${GREEN}GHCR authentication successful${NC}"
    else
        echo -e "${YELLOW}GHCR authentication skipped${NC}"
    fi
else
    echo "Skipping GHCR authentication"
fi

echo ""

# Step 7: Start Docker Compose
echo "=========================================="
echo "Step 7: Starting Jambonz Services"
echo "=========================================="

echo "Pulling Docker images (this may take several minutes)..."
docker compose pull

echo ""
echo "Starting services..."
docker compose up -d

echo ""
echo "Waiting for services to start..."
sleep 10

echo ""
echo "Service status:"
docker compose ps

echo ""

# Step 8: Update SBC IP addresses
echo "=========================================="
echo "Step 8: Updating SBC IP Addresses"
echo "=========================================="

echo "Updating SBC IP addresses in database..."
if [ -f update-sbc-ip.sh ]; then
    chmod +x update-sbc-ip.sh
    ./update-sbc-ip.sh
else
    echo -e "${YELLOW}update-sbc-ip.sh not found, updating manually...${NC}"
    docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
DELETE FROM sbc_addresses WHERE ipv4 IN ('52.55.111.178', '3.34.102.122', '127.0.0.1', 'localhost');
INSERT INTO sbc_addresses (sbc_address_sid, ipv4, port, service_provider_sid)
VALUES ('f6567ae1-bf97-49af-8931-ca014b689995', '$PUBLIC_IP', 5060, NULL)
ON DUPLICATE KEY UPDATE ipv4 = '$PUBLIC_IP', port = 5060;
SELECT 'SBC addresses updated' AS status;
SELECT ipv4, port FROM sbc_addresses;
EOF
fi

echo ""

# Step 9: Security Group Configuration
echo "=========================================="
echo "Step 9: AWS Security Group Configuration"
echo "=========================================="

echo -e "${YELLOW}IMPORTANT: Configure your AWS Security Group with these rules:${NC}"
echo ""
echo "Inbound Rules Required:"
echo "  - Type: Custom UDP, Port: 5060, Source: 0.0.0.0/0 (SIP signaling)"
echo "  - Type: Custom TCP, Port: 5060, Source: 0.0.0.0/0 (SIP signaling)"
echo "  - Type: Custom UDP, Port: 40000-60000, Source: 0.0.0.0/0 (RTP media)"
echo "  - Type: HTTP, Port: 80, Source: 0.0.0.0/0 (Optional: for webapp)"
echo "  - Type: HTTPS, Port: 443, Source: 0.0.0.0/0 (Optional: for webapp)"
echo "  - Type: Custom TCP, Port: 3000, Source: 0.0.0.0/0 (API server)"
echo "  - Type: Custom TCP, Port: 3001, Source: 0.0.0.0/0 (Webapp)"
echo "  - Type: SSH, Port: 22, Source: Your IP (for management)"
echo ""
echo "To configure:"
echo "  1. Go to AWS Console → EC2 → Security Groups"
echo "  2. Select your instance's security group"
echo "  3. Add the inbound rules listed above"
echo ""
read -p "Press Enter after you've configured the security group..."

echo ""

# Step 10: Verification
echo "=========================================="
echo "Step 10: Verification"
echo "=========================================="

echo "Checking service health..."
echo ""

# Check if containers are running
if docker compose ps | grep -q "Up"; then
    echo -e "${GREEN}✓ Docker containers are running${NC}"
else
    echo -e "${RED}✗ Some containers are not running${NC}"
    echo "Check logs with: docker compose logs"
fi

# Check if webapp is accessible
echo ""
echo "Testing webapp accessibility..."
if curl -s --max-time 5 http://localhost:3001 > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Webapp is accessible on localhost:3001${NC}"
else
    echo -e "${YELLOW}⚠ Webapp not yet accessible (may still be starting)${NC}"
fi

# Check if API is accessible
echo ""
echo "Testing API accessibility..."
if curl -s --max-time 5 http://localhost:3000/health > /dev/null 2>&1; then
    echo -e "${GREEN}✓ API is accessible on localhost:3000${NC}"
else
    echo -e "${YELLOW}⚠ API not yet accessible (may still be starting)${NC}"
fi

echo ""

# Final Summary
echo "=========================================="
echo "Setup Complete!"
echo "=========================================="
echo ""
echo -e "${GREEN}Jambonz is now running on your EC2 instance!${NC}"
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
echo "Useful commands:"
echo "  - View logs: cd $INSTALL_DIR/docker && docker compose logs -f"
echo "  - Stop services: cd $INSTALL_DIR/docker && docker compose down"
echo "  - Start services: cd $INSTALL_DIR/docker && docker compose up -d"
echo "  - Restart services: cd $INSTALL_DIR/docker && docker compose restart"
echo "  - Update SBC IP: cd $INSTALL_DIR/docker && ./update-sbc-ip.sh"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Configure AWS Security Group (if not done already)"
echo "  2. Add GCP credentials to credentials/gcp.json (for TTS/STT)"
echo "  3. Log into webapp and change default password"
echo "  4. Configure your account, applications, and carriers"
echo "  5. Share SIP signaling IP ($PUBLIC_IP:5060) with carriers for whitelisting"
echo ""
echo "=========================================="

