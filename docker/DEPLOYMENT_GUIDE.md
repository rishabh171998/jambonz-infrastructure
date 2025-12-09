# Deployment Guide for EC2

This guide explains how to deploy updates to your Jambonz infrastructure on EC2, including force recreating containers after pulling the latest changes.

## Quick Deployment

### Option 1: Using the Deployment Script (Recommended)

```bash
# SSH into your EC2 instance
ssh -i ~/.ssh/your-key.pem admin@your-ec2-ip

# Navigate to the docker directory
cd /opt/jambonz-infrastructure/docker

# Set HOST_IP (if not already set)
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
# OR use your Elastic IP:
# export HOST_IP=your-elastic-ip

# Run the deployment script
./deploy-update.sh
```

The script will:
1. Pull latest code from git
2. Pull latest Docker images
3. Stop existing containers
4. Force recreate all containers with new configuration
5. Verify services are running

### Option 2: Manual Deployment

```bash
# SSH into your EC2 instance
ssh -i ~/.ssh/your-key.pem admin@your-ec2-ip

# Navigate to the docker directory
cd /opt/jambonz-infrastructure/docker

# Set HOST_IP
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Pull latest code (if using git)
cd /opt/jambonz-infrastructure
git pull
cd docker

# Pull latest Docker images
sudo docker compose pull

# Stop existing containers
sudo docker compose down

# Force recreate containers with new configuration
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate --remove-orphans

# Verify services
sudo docker compose ps
```

## Force Recreate Specific Services

If you only need to recreate specific services:

```bash
cd /opt/jambonz-infrastructure/docker

# Recreate rtpengine (after port range changes)
sudo docker compose up -d --force-recreate rtpengine

# Recreate drachtio-sbc
sudo docker compose up -d --force-recreate drachtio-sbc

# Recreate all services
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate
```

## After Configuration Changes

### After RTP Port Range Changes (10000-70000)

```bash
cd /opt/jambonz-infrastructure/docker

# 1. Pull latest code
git pull

# 2. Recreate rtpengine with new port range
sudo docker compose up -d --force-recreate rtpengine

# 3. Verify rtpengine is using new ports
sudo docker compose logs rtpengine | grep "port-min\|port-max"

# 4. Update AWS Security Group to allow 10000-70000
# (See AWS_SECURITY_GROUP_SETUP.md)
```

### After docker-compose.yaml Changes

```bash
cd /opt/jambonz-infrastructure/docker

# Pull latest code
git pull

# Force recreate all containers
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate --remove-orphans

# Verify
sudo docker compose ps
```

## Updating Security Group for New Port Range

After updating to port range 10000-70000, update your AWS Security Group:

### Using AWS Console

1. Go to **EC2 → Security Groups → Your Security Group**
2. **Edit inbound rules**
3. **Remove old RTP rule** (if exists): UDP 40000-60000
4. **Add new RTP rule**:
   - Type: `Custom UDP`
   - Port Range: `10000-70000`
   - Source: `0.0.0.0/0` (or restrict to carrier IPs)
   - Description: `RTP Media (Universal range)`
5. **Save rules**

### Using AWS CLI

```bash
# Get your security group ID
SG_ID=$(aws ec2 describe-instances \
  --instance-ids i-your-instance-id \
  --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' \
  --output text)

# Remove old RTP rule (if exists)
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol udp \
  --port 40000 \
  --cidr 0.0.0.0/0

# Add new RTP rule (10000-70000)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol udp \
  --port 10000 \
  --cidr 0.0.0.0/0 \
  --ip-permissions IpProtocol=udp,FromPort=10000,ToPort=70000,IpRanges=[{CidrIp=0.0.0.0/0,Description="RTP Media (Universal range)"}]
```

## Verification Steps

After deployment, verify everything is working:

```bash
cd /opt/jambonz-infrastructure/docker

# 1. Check all services are running
sudo docker compose ps

# 2. Check rtpengine port range
sudo docker compose logs rtpengine | grep -i "port-min\|port-max"
# Should show: --port-min 10000 --port-max 70000

# 3. Check drachtio-sbc is listening
sudo netstat -tulpn | grep 5060
# Should show UDP and TCP on port 5060

# 4. Test API Server
curl http://localhost:3000/health

# 5. Test Webapp
curl http://localhost:3001

# 6. Check RTP ports are listening
sudo netstat -tulpn | grep -E "10000|20000|30000|40000|50000|60000|70000" | head -5
```

## Troubleshooting

### Containers Not Starting

```bash
# Check logs for errors
sudo docker compose logs

# Check specific service
sudo docker compose logs rtpengine
sudo docker compose logs drachtio-sbc

# Restart specific service
sudo docker compose restart rtpengine
```

### Port Already in Use

```bash
# Check what's using the port
sudo lsof -i :5060
sudo lsof -i :10000-70000

# Kill process if needed (be careful!)
sudo kill -9 <PID>
```

### HOST_IP Not Set

```bash
# Set HOST_IP
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Or create .env file
echo "HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)" > .env

# Restart with HOST_IP
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate
```

### RTP Ports Not Accessible

1. **Check Security Group**: Ensure UDP 10000-70000 is open
2. **Check rtpengine logs**: `sudo docker compose logs rtpengine`
3. **Verify HOST_IP**: `echo $HOST_IP`
4. **Test from external**: `nc -uv your-ec2-ip 10000`

## Rollback

If something goes wrong, you can rollback:

```bash
cd /opt/jambonz-infrastructure/docker

# Rollback to previous git commit
git log --oneline  # Find previous commit
git checkout <previous-commit-hash>

# Recreate containers with previous configuration
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate
```

## Best Practices

1. **Always set HOST_IP** before deploying
2. **Update Security Group** before deploying port range changes
3. **Test in staging** before production deployment
4. **Monitor logs** after deployment: `sudo docker compose logs -f`
5. **Verify services** are accessible after deployment
6. **Keep backups** of your database before major updates

## Quick Reference

```bash
# Full deployment
./deploy-update.sh

# Quick restart (no pull)
sudo docker compose restart

# Force recreate everything
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate --remove-orphans

# View logs
sudo docker compose logs -f [service-name]

# Check status
sudo docker compose ps

# Update SBC IP in database
./update-sbc-ip.sh
```

