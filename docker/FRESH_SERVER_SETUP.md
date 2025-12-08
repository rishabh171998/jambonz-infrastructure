# Fresh Server Setup Guide - Complete Installation

This guide will help you set up Jambonz on a completely fresh EC2 instance with nothing pre-installed.

## Prerequisites

- Fresh EC2 instance (Debian/Ubuntu recommended)
- SSH access to the server
- Your EC2 public IP: `13.203.223.245`

## Step 1: Connect to Your Server

```bash
# From your local machine
chmod 400 rishabh.pem
ssh -i rishabh.pem admin@13.203.223.245
```

## Step 2: Run the Complete Setup Script

Once connected to your server, run this single command:

```bash
curl -fsSL https://raw.githubusercontent.com/rishabh171998/jambonz-infrastructure/main/docker/setup-fresh-server.sh | bash
```

**OR** if you prefer to download and review first:

```bash
# Download the script
curl -o /tmp/setup-jambonz.sh https://raw.githubusercontent.com/rishabh171998/jambonz-infrastructure/main/docker/setup-fresh-server.sh

# Review it (optional)
cat /tmp/setup-jambonz.sh

# Make it executable and run
chmod +x /tmp/setup-jambonz.sh
sudo /tmp/setup-jambonz.sh
```

## What the Script Does

The setup script will automatically:

1. ✅ **Update system packages**
2. ✅ **Install Docker** (if not present)
3. ✅ **Install Docker Compose** (if not present)
4. ✅ **Install Git** (if not present)
5. ✅ **Install required tools** (curl, wget, etc.)
6. ✅ **Clone the repository** to `/opt/jambonz-infrastructure`
7. ✅ **Initialize git submodules**
8. ✅ **Detect public IP** automatically
9. ✅ **Create .env file** with correct HOST_IP
10. ✅ **Start Docker Compose services**
11. ✅ **Update SBC IP addresses** in database
12. ✅ **Display access information**

## Step 3: Configure AWS Security Group

**CRITICAL**: Before accessing the webapp, configure your security group:

### Option A: Using AWS Console

1. Go to **EC2 → Instances → Select your instance**
2. Click on **Security** tab
3. Click on the security group name
4. Click **Edit inbound rules**
5. Add these rules:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 5060 | 0.0.0.0/0 | SIP Signaling |
| Custom TCP | TCP | 5060 | 0.0.0.0/0 | SIP Signaling |
| Custom UDP | UDP | 40000-60000 | 0.0.0.0/0 | RTP Media |
| Custom TCP | TCP | 3000 | 0.0.0.0/0 | API Server |
| Custom TCP | TCP | 3001 | 0.0.0.0/0 | Webapp |
| SSH | TCP | 22 | Your IP | Management |

6. Click **Save rules**

### Option B: Using AWS CLI

```bash
# Get your security group ID
SG_ID=$(aws ec2 describe-instances --instance-ids i-068137d3d519be41f --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Add rules
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 5060 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5060 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 40000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 60000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3001 --cidr 0.0.0.0/0
```

## Step 4: Access the Webapp

After the setup completes (takes 5-10 minutes):

1. Open your browser: **http://13.203.223.245:3001**
2. Login with:
   - Username: `admin`
   - Password: `admin`
3. You'll be forced to change the password on first login

## Step 5: Verify Installation

```bash
# Check if all containers are running
cd /opt/jambonz-infrastructure/docker
docker compose ps

# Check logs
docker compose logs -f

# Test webapp
curl http://localhost:3001

# Test API
curl http://localhost:3000/health
```

## Step 6: Configure SIP Realm (Account Level)

1. Log into webapp: **http://13.203.223.245:3001**
2. Go to **Accounts → Create Account**
3. In **"SIP realm"** field, enter your domain:
   - Option A: Use subdomain: `account1` (becomes `account1.sip.jambonz.cloud`)
   - Option B: Use custom domain: `sip.yourcompany.com` (requires DNS setup)
4. Save the account

**Important:**
- ❌ Don't use IP address as SIP realm
- ❌ Don't duplicate SIP realm across accounts
- ✅ SIP Realm is different from SIP Signaling IP

## Step 7: Verify SIP Signaling IP

1. Log into webapp
2. Go to **Carriers → Create Carrier**
3. Look for: **"Have your carriers whitelist our SIP signaling IPs"**
4. It should show: **13.203.223.245:5060**

If it shows example IPs, run:
```bash
cd /opt/jambonz-infrastructure/docker
./update-sbc-ip.sh
```

## Manual Setup (Alternative)

If you prefer to set up manually instead of using the script:

### 1. Install Docker

```bash
# Update system
sudo apt-get update
sudo apt-get install -y ca-certificates curl gnupg lsb-release

# Add Docker's official GPG key
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Set up repository
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start Docker
sudo systemctl enable docker
sudo systemctl start docker

# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker
```

### 2. Install Git

```bash
sudo apt-get install -y git
```

### 3. Clone Repository

```bash
cd /opt
sudo git clone https://github.com/rishabh171998/jambonz-infrastructure.git
cd jambonz-infrastructure
sudo git submodule update --init
sudo chown -R $USER:$USER /opt/jambonz-infrastructure
```

### 4. Configure Environment

```bash
cd /opt/jambonz-infrastructure/docker

# Get public IP
PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Create .env file
cat > .env << EOF
HOST_IP=$PUBLIC_IP
EOF
```

### 5. Start Services

```bash
cd /opt/jambonz-infrastructure/docker
docker compose up -d

# Wait for services to start (2-3 minutes)
sleep 180

# Update SBC IP addresses
./update-sbc-ip.sh
```

## Troubleshooting

### Containers not starting
```bash
cd /opt/jambonz-infrastructure/docker
docker compose logs
docker compose ps
```

### Can't access webapp
1. Check security group rules
2. Check if containers are running: `docker compose ps`
3. Check webapp logs: `docker compose logs webapp`

### Permission denied for Docker
```bash
sudo usermod -aG docker $USER
newgrp docker
# Or logout and login again
```

### Git submodule issues
```bash
cd /opt/jambonz-infrastructure
git submodule update --init --recursive
```

## Next Steps

1. ✅ Configure security group (if not done)
2. ✅ Add TTS/STT credentials (GCP or AWS)
3. ✅ Log into webapp and change password
4. ✅ Create account and set SIP realm domain
5. ✅ Create applications
6. ✅ Configure SIP carriers
7. ✅ Share SIP IP (13.203.223.245:5060) with carriers
8. ✅ Test with a softphone or SIP device

## Useful Commands

```bash
cd /opt/jambonz-infrastructure/docker

# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f drachtio-sbc
docker compose logs -f rtpengine
docker compose logs -f webapp

# Restart services
docker compose restart

# Stop services
docker compose down

# Start services
docker compose up -d

# Update SBC IP addresses
./update-sbc-ip.sh

# Check service status
docker compose ps
```

## Support

- Check logs: `docker compose logs -f`
- Review documentation: `/opt/jambonz-infrastructure/docker/README.md`
- AWS deployment guide: `/opt/jambonz-infrastructure/docker/AWS_DEPLOYMENT.md`

