# AWS Deployment Guide for Docker-based Jambonz

## Overview

The Docker Compose configuration will work on AWS, but there are some important considerations and adjustments needed for proper AWS deployment.

## What Works Automatically ✅

### Container Name Resolution
- **All container-to-container communication using service names will work perfectly**
- Docker Compose creates DNS entries for each service
- Examples that work:
  - `mysql`, `redis`, `influxdb` - database connections
  - `drachtio-sbc`, `drachtio-fs` - Drachtio connections
  - `rtpengine:22222` - RTPEngine NG protocol
  - `sbc-inbound:4000`, `sbc-outbound:4000` - HTTP routing
  - `freeswitch:8021` - FreeSWITCH Event Socket
  - `api-server`, `webapp` - API connections

### Internal Network
- Docker bridge network (`172.10.0.0/16`) works fine
- No conflicts with AWS VPC (AWS typically uses `10.0.0.0/16` or `172.31.0.0/16`)

## What Needs AWS-Specific Configuration ⚠️

### 1. HOST_IP Environment Variable (CRITICAL)

**Required:** Set `HOST_IP` to your AWS EC2 instance's **public IP** or **Elastic IP**.

**Option A: Use Elastic IP (Recommended)**
```bash
# Allocate Elastic IP in AWS Console, then:
export HOST_IP=54.123.45.67  # Your Elastic IP
```

**Option B: Auto-detect Public IP**
```bash
# Get public IP automatically
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
```

**Option C: Use .env file**
Create/edit `.env` file:
```bash
HOST_IP=54.123.45.67  # Your AWS public IP or Elastic IP
```

### 2. SIP Contact Headers

The `drachtio-sbc` service uses `${HOST_IP}` in the SIP contact header, which is correct for AWS:
```yaml
command: ["drachtio", "--contact", "sip:${HOST_IP};transport=udp,tcp", ...]
```

**✅ This is already configured correctly** - it will use your AWS public IP.

### 3. RTP Engine Interfaces

RTPEngine needs to know the public IP for media routing:
```yaml
command: ["rtpengine", "--interface", "private/172.10.0.11", "--interface", "public/172.10.0.11!${HOST_IP}", ...]
```

**✅ This is already configured correctly** - uses `${HOST_IP}` for public interface.

### 4. JAMBONES_SBCS Configuration

Currently set to `drachtio-sbc` (container name). For SIP signaling, this might need to be the public IP depending on how the feature server connects.

**Current:** `JAMBONES_SBCS: drachtio-sbc`

**For AWS, you might need:**
```yaml
JAMBONES_SBCS: ${HOST_IP}  # or keep as drachtio-sbc if internal routing works
```

**Recommendation:** Try `drachtio-sbc` first. If SIP routing doesn't work, change to `${HOST_IP}`.

### 5. API_BASE_URL

Currently uses `${HOST_IP}`:
```yaml
API_BASE_URL: http://${HOST_IP}:3000/v1
```

**✅ This is correct for AWS** - webapp will connect to API using public IP.

## AWS-Specific Setup Steps

### Step 1: Launch EC2 Instance

1. **Instance Type:** Minimum `t3.medium` (2 vCPU, 4GB RAM)
   - Recommended: `c5.xlarge` or larger for production
2. **Storage:** Minimum 50GB EBS volume (100GB recommended)
3. **OS:** Ubuntu 22.04 LTS or Amazon Linux 2023
4. **Security Group:** Configure as per `AWS_SECURITY_GROUP_SETUP.md`

### Step 2: Install Docker and Docker Compose

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-plugin
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker $USER

# Amazon Linux 2023
sudo yum install -y docker
sudo systemctl enable docker
sudo systemctl start docker
sudo usermod -aG docker ec2-user
```

### Step 3: Allocate Elastic IP (Recommended)

```bash
# In AWS Console:
# 1. EC2 → Elastic IPs → Allocate Elastic IP
# 2. Associate with your EC2 instance
# 3. Note the Elastic IP address
```

### Step 4: Configure HOST_IP

```bash
cd /path/to/jambonz-infrastructure/docker

# Option 1: Create .env file
cat > .env << EOF
HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
EOF

# Option 2: Export as environment variable
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)

# Option 3: Use Elastic IP (recommended)
export HOST_IP=54.123.45.67  # Your Elastic IP
```

### Step 5: Set Up Credentials

```bash
# Copy GCP credentials (if using Google TTS/STT)
cp /path/to/gcp.json credentials/gcp.json

# Or set AWS credentials for Polly (if using AWS TTS)
# These can be set via IAM role or environment variables
```

### Step 6: Start Docker Compose

```bash
# Pull images first (if needed)
docker-compose pull

# Start services
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f
```

### Step 7: Update SBC IP Addresses in Database (CRITICAL)

**This is essential for the webapp to show the correct SIP signaling IPs!**

The webapp displays SIP IPs from the `sbc_addresses` table. The initial database has example IPs that need to be updated with your actual AWS public IP.

```bash
# Option 1: Use the automated script (recommended)
./update-sbc-ip.sh

# Option 2: Manual update via MySQL
docker-compose exec mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sbc_addresses SET ipv4 = '${HOST_IP}' WHERE ipv4 IN ('52.55.111.178', '3.34.102.122');
-- Or insert if no records exist
INSERT INTO sbc_addresses (sbc_address_sid, ipv4, port) 
VALUES ('f6567ae1-bf97-49af-8931-ca014b689995', '${HOST_IP}', 5060)
ON DUPLICATE KEY UPDATE ipv4 = '${HOST_IP}';
SELECT * FROM sbc_addresses;
EOF
```

**Why this matters:**
- When creating carriers in the webapp, it shows "Have your carriers whitelist our SIP signaling IPs"
- This displays IPs from the `sbc_addresses` table
- Carriers need to whitelist these IPs to send SIP traffic to your system
- **If this isn't updated, carriers will see example IPs that don't work!**

### Step 8: Configure Route53 DNS (If Using Custom Domain)

**If you're using a custom SIP realm domain** (e.g., `sip.yourcompany.com`), you need to configure Route53 DNS records.

**Quick Setup:**
1. Go to **Route53 → Hosted zones → Your domain**
2. Create **A record**:
   - Name: `sip` (or `*.sip` for wildcard)
   - Type: `A`
   - Value: Your EC2 public IP (e.g., `13.203.223.245`)
   - TTL: `300`
3. Verify: `dig sip.yourcompany.com` should return your EC2 IP

**For detailed Route53 setup, see:** `AWS_ROUTE53_SETUP.md`

### Step 9: Configure SIP Realm Domain (Account Level)

**What is SIP Realm?**
- SIP realm is the domain that SIP devices register to (e.g., `sip.yourcompany.com` or `account1.sip.jambonz.cloud`)
- Stored at **account level** in `accounts.sip_realm` column (just for storage)
- Each account must have a unique SIP realm

**✅ What TO Do:**

1. **Set in Webapp**: Accounts → Create/Edit Account → Enter SIP realm (e.g., `sip.yourcompany.com` or `account1`)
2. **DNS Setup** (if using custom domain): Create A record pointing to your EC2 IP
3. **Verify**: `docker-compose exec mysql mysql -ujambones -pjambones jambones -e "SELECT name, sip_realm FROM accounts;"`

**❌ What NOT To Do:**

- ❌ Don't use IP address: `sip_realm = '13.203.223.245'` (use domain name)
- ❌ Don't duplicate: Each account needs unique SIP realm
- ❌ Don't forget DNS: Custom domains need DNS A record to EC2 IP
- ❌ Don't confuse with SIP Signaling IP: SIP Realm = device registration domain (account level), SIP IP = carrier traffic (system level in `sbc_addresses`)

**Examples:**
- `customer1.sip.jambonz.cloud` (uses default root domain, no DNS needed)
- `sip.mycompany.com` (custom domain, requires DNS: `sip.mycompany.com A → 13.203.223.245`)

## Potential Issues and Solutions

### Issue 1: Container Names Not Resolving

**Symptom:** Services can't connect to each other using container names.

**Solution:** 
- Ensure all services are on the same Docker network (`jambonz`)
- Check with: `docker network inspect docker_jambonz`
- Restart services: `docker-compose restart`

### Issue 2: SIP Traffic Not Reaching Containers

**Symptom:** External SIP devices can't connect.

**Solutions:**
1. **Check Security Group:** Ensure ports 5060/UDP, 5060/TCP are open
2. **Check HOST_IP:** Verify `${HOST_IP}` is set to public IP
3. **Check Route Tables:** Ensure EC2 instance has internet gateway route
4. **Check Elastic IP:** If using Elastic IP, ensure it's associated

### Issue 3: RTP Media Not Working

**Symptom:** Calls connect but no audio.

**Solutions:**
1. **Security Group:** Ensure UDP ports 40000-60000 are open
2. **HOST_IP:** Must be set correctly for RTPEngine public interface
3. **Check RTPEngine logs:** `docker-compose logs rtpengine`

### Issue 4: Database Connection Issues

**Symptom:** Services can't connect to MySQL/Redis.

**Solution:**
- Container names (`mysql`, `redis`) should work automatically
- If not, check network: `docker network inspect docker_jambonz`
- Verify services are running: `docker-compose ps`

### Issue 5: Feature Server Can't Reach SBC

**Symptom:** Feature server can't send SIP to SBC.

**Current Config:** `JAMBONES_SBCS: drachtio-sbc`

**If this doesn't work, try:**
```yaml
JAMBONES_SBCS: ${HOST_IP}  # Use public IP instead
```

## Network Architecture on AWS

```
Internet
   │
   ├─→ AWS Security Group (ports 5060, 40000-60000, 3000, 3001, etc.)
   │
   ├─→ EC2 Instance (Public IP: ${HOST_IP})
   │   │
   │   ├─→ Docker Bridge Network (172.10.0.0/16)
   │   │   │
   │   │   ├─→ drachtio-sbc (172.10.0.10) ← SIP signaling
   │   │   ├─→ rtpengine (172.10.0.11) ← RTP media
   │   │   ├─→ mysql (172.10.0.2) ← Database
   │   │   ├─→ redis (172.10.0.3) ← Cache
   │   │   ├─→ api-server (172.10.0.30) ← API
   │   │   ├─→ webapp (172.10.0.31) ← Web UI
   │   │   └─→ ... (other services)
   │   │
   │   └─→ Docker Host Network
   │       └─→ Port mappings to host
```

## Testing Your Deployment

### 1. Check All Containers Are Running
```bash
docker-compose ps
# All services should show "Up" status
```

### 2. Test Internal Connectivity
```bash
# Test MySQL connection
docker-compose exec api-server ping -c 3 mysql

# Test Redis connection
docker-compose exec api-server ping -c 3 redis

# Test Drachtio connection
docker-compose exec sbc-inbound ping -c 3 drachtio-sbc
```

### 3. Test External Access
```bash
# Test API
curl http://${HOST_IP}:3000/health

# Test Webapp
curl http://${HOST_IP}:3001

# Test SIP Port (should timeout, but port should be open)
nc -uv ${HOST_IP} 5060
```

### 4. Check Logs
```bash
# All services
docker-compose logs

# Specific service
docker-compose logs drachtio-sbc
docker-compose logs rtpengine
docker-compose logs feature-server
```

## Production Considerations

### 1. Use Elastic IP
- Prevents IP changes on instance restart
- Required for carrier trunking

### 2. Use IAM Roles
- Don't hardcode AWS credentials
- Use IAM roles for EC2 instance

### 3. Enable CloudWatch Logs
- Consider using Docker logging driver for CloudWatch
- Or use `docker-compose logs` with log rotation

### 4. Database Backup
- The `data_volume/` directory contains MySQL data
- Set up regular backups to S3

### 5. Monitoring
- Set up CloudWatch alarms for CPU, memory, network
- Monitor Docker container health

### 6. Security
- Use strong passwords (change from defaults)
- Enable AWS WAF for HTTP/HTTPS traffic
- Consider using private subnet with NAT Gateway

## Summary

**✅ What Works:**
- Container name resolution (all internal communication)
- Docker networking
- Service discovery
- Most configuration

**⚠️ What Needs Configuration:**
- `HOST_IP` must be set to AWS public IP/Elastic IP
- **SBC IP addresses in database must be updated** (use `update-sbc-ip.sh`)
- Security groups must allow required ports
- Elastic IP recommended for production

**🔧 Optional Adjustments:**
- `JAMBONES_SBCS` might need to be public IP instead of container name
- Consider using AWS RDS for MySQL (instead of container)
- Consider using ElastiCache for Redis (instead of container)

## Critical: SIP Signaling IP Display

**IMPORTANT:** The webapp shows SIP signaling IPs from the `sbc_addresses` database table. These must be updated with your actual AWS public IP, otherwise:

1. ❌ Carriers will see example IPs (52.55.111.178, 3.34.102.122) that don't work
2. ❌ Carriers won't be able to whitelist your actual IP
3. ❌ SIP traffic from carriers will be rejected

**Solution:** Run `./update-sbc-ip.sh` after starting Docker Compose to update the database with your actual public IP.

The configuration is **AWS-ready** - just set `HOST_IP` correctly, update SBC IPs in database, and configure security groups!

