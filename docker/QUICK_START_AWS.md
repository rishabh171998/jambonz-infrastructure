# Quick Start Guide for AWS EC2 Deployment

## Your EC2 Instance Details
- **Instance ID**: i-068137d3d519be41f
- **Public IP**: 13.203.223.245
- **Instance Type**: t3.medium
- **OS**: Debian 13

## Step 1: Connect to Your EC2 Instance

```bash
ssh -i ~/.ssh/rishabh.pem admin@13.203.223.245
# Or use your preferred SSH method
```

## Step 2: Run the Setup Script

```bash
# Download and run the setup script
curl -o /tmp/setup-jambonz.sh https://raw.githubusercontent.com/jambonz/jambonz-infrastructure/main/docker/setup-aws-ec2.sh
chmod +x /tmp/setup-jambonz.sh
sudo /tmp/setup-jambonz.sh
```

**OR** if you prefer to clone the repository first:

```bash
# Clone the repository
cd /opt
sudo git clone https://github.com/jambonz/jambonz-infrastructure.git
cd jambonz-infrastructure/docker
sudo chown -R $USER:$USER /opt/jambonz-infrastructure

# Run the setup script
./setup-aws-ec2.sh
```

## Step 3: Configure AWS Security Group

**CRITICAL**: You must configure your security group to allow traffic.

### Option A: Using AWS Console

1. Go to **EC2 → Instances → Select your instance (i-068137d3d519be41f)**
2. Click on **Security** tab
3. Click on the security group name
4. Click **Edit inbound rules**
5. Add these rules:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 5060 | 0.0.0.0/0 | SIP Signaling (UDP) |
| Custom TCP | TCP | 5060 | 0.0.0.0/0 | SIP Signaling (TCP) |
| Custom TCP | TCP | 5061 | 0.0.0.0/0 | SIP TLS (if using TLS/SRTP) |
| Custom UDP | UDP | 40000-60000 | 0.0.0.0/0 | RTP Media |
| Custom TCP | TCP | 3000 | 0.0.0.0/0 | API Server |
| Custom TCP | TCP | 3001 | 0.0.0.0/0 | Webapp |
| SSH | TCP | 22 | Your IP | Management |

6. Click **Save rules**

### Option B: Using AWS CLI

```bash
# Get your security group ID (replace with your actual SG ID)
SG_ID=$(aws ec2 describe-instances --instance-ids i-068137d3d519be41f --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Add SIP UDP
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 5060 --cidr 0.0.0.0/0

# Add SIP TCP
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5060 --cidr 0.0.0.0/0

# Add SIP TLS (if using TLS/SRTP)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5061 --cidr 0.0.0.0/0

# Add RTP Media (UDP 40000-60000)
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 40000 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol udp --port 60000 --cidr 0.0.0.0/0

# Add API
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0

# Add Webapp
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3001 --cidr 0.0.0.0/0
```

## Step 4: Verify Installation

After the setup script completes:

```bash
# Check if all containers are running
cd /opt/jambonz-infrastructure/docker
docker compose ps

# Check logs
docker compose logs -f

# Test webapp (should return HTML)
curl http://localhost:3001

# Test API (should return health status)
curl http://localhost:3000/health
```

## Step 5: Access the Webapp

1. Open your browser and go to: **http://13.203.223.245:3001**
2. Login with:
   - Username: `admin`
   - Password: `admin`
3. You'll be forced to change the password on first login

## Step 6: Verify SIP Signaling IP

1. Log into the webapp
2. Go to **Carriers → Create Carrier** (or edit existing)
3. Look for the section: **"Have your carriers whitelist our SIP signaling IPs"**
4. It should show: **13.203.223.245:5060**

If it shows example IPs (like 52.55.111.178), run:

```bash
cd /opt/jambonz-infrastructure/docker
./update-sbc-ip.sh
```

## Important Notes

### SIP Signaling IP for Carriers
- **IP Address**: 13.203.223.245
- **Port**: 5060
- **Protocol**: UDP and TCP

Share this with your carriers so they can whitelist it.

### SIP Realm Domain (Account Level)
**What is it?** Domain that SIP devices register to (e.g., `sip.yourcompany.com`). Stored per account.

**✅ To Do:**
- Set in webapp: Accounts → Create/Edit → SIP realm field
- Use domain name (not IP): `sip.yourcompany.com` or `account1` (becomes `account1.sip.jambonz.cloud`)
- Configure DNS if using custom domain: `sip.yourcompany.com A → 13.203.223.245`

**❌ Not To Do:**
- Don't use IP address as SIP realm
- Don't use same SIP realm for multiple accounts
- Don't forget DNS for custom domains

**Note:** SIP Realm (account level) is different from SIP Signaling IP (system level). SIP IP is for carriers, SIP Realm is for device registration.

### Elastic IP (Recommended)
Your current public IP (13.203.223.245) will change if you stop/restart the instance. For production:

1. Allocate an Elastic IP in AWS Console
2. Associate it with your instance
3. Update HOST_IP in `.env` file:
   ```bash
   cd /opt/jambonz-infrastructure/docker
   # Edit .env and change HOST_IP to your Elastic IP
   # Then restart services
   docker compose down
   docker compose up -d
   ./update-sbc-ip.sh
   ```

### Credentials Setup

**For Google Cloud TTS/STT:**
```bash
# Download service account JSON from GCP Console
# Save it as:
/opt/jambonz-infrastructure/docker/credentials/gcp.json
```

**For AWS Polly TTS:**
- Use IAM role (recommended), or
- Set in `.env` file:
  ```
  AWS_ACCESS_KEY_ID=your-key
  AWS_SECRET_ACCESS_KEY=your-secret
  AWS_REGION=ap-south-1
  ```

## Troubleshooting

### Containers not starting
```bash
cd /opt/jambonz-infrastructure/docker
docker compose logs
docker compose ps
```

### Can't access webapp from browser
1. Check security group rules
2. Check if containers are running: `docker compose ps`
3. Check webapp logs: `docker compose logs webapp`

### SIP traffic not working
1. Verify security group allows UDP/TCP 5060
2. Check HOST_IP is set correctly: `grep HOST_IP .env`
3. Check drachtio-sbc logs: `docker compose logs drachtio-sbc`
4. Verify SBC IP in database: `./update-sbc-ip.sh`

### RTP media not working
1. Verify security group allows UDP 40000-60000
2. Check rtpengine logs: `docker compose logs rtpengine`
3. Verify HOST_IP is set correctly

## Useful Commands

```bash
cd /opt/jambonz-infrastructure/docker

# View all logs
docker compose logs -f

# View specific service logs
docker compose logs -f drachtio-sbc
docker compose logs -f rtpengine
docker compose logs -f feature-server
docker compose logs -f api-server
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

# Access MySQL
docker compose exec mysql mysql -ujambones -pjambones jambones

# Access Redis
docker compose exec redis redis-cli
```

## Next Steps

1. ✅ Configure security group (if not done)
2. ✅ Add TTS/STT credentials (GCP or AWS)
3. ✅ Log into webapp and change password
4. ✅ Create account and set SIP realm domain (account level)
5. ✅ Create applications
6. ✅ Configure SIP carriers
7. ✅ Share SIP IP (13.203.223.245:5060) with carriers
8. ✅ Configure DNS for SIP realm (if using custom domain)
9. ✅ Test with a softphone or SIP device

## Support

- Check logs: `docker compose logs -f`
- Review documentation: `/opt/jambonz-infrastructure/docker/README.md`
- AWS deployment guide: `/opt/jambonz-infrastructure/docker/AWS_DEPLOYMENT.md`

