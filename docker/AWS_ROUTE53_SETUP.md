# AWS Route53 DNS Configuration for Jambonz SIP Realm

This guide explains how to configure Route53 DNS records for your Jambonz SIP realm domain.

## Overview

When you set a SIP realm domain in Jambonz (e.g., `sip.yourcompany.com`), you need DNS records pointing to your EC2 instance's public IP so SIP devices can resolve and connect to your server.

## Prerequisites

1. **Domain registered in Route53** (or transferred to Route53)
2. **EC2 instance with Jambonz running**
3. **Public IP or Elastic IP** of your EC2 instance (e.g., `13.203.223.245`)

## Step 1: Get Your EC2 Public IP

```bash
# From your EC2 instance
curl http://169.254.169.254/latest/meta-data/public-ipv4

# Or check in AWS Console: EC2 → Instances → Your Instance → Public IPv4 address
```

**Recommended:** Use an **Elastic IP** so it doesn't change when you restart the instance.

## Step 2: Configure Route53 Hosted Zone

### Option A: Using AWS Console

1. **Go to Route53** → **Hosted zones**
2. **Select your domain** (e.g., `yourcompany.com`)
3. **Click "Create record"**

#### For SIP Realm: `sip.yourcompany.com`

**IMPORTANT:** You need BOTH records if using subdomains!

**Record 1: Base Domain (Required)**
- **Record name**: `sip`
- **Record type**: `A`
- **Value**: Your EC2 public IP (e.g., `13.203.223.245`)
- **TTL**: `300` (5 minutes) or `60` (1 minute) for faster updates
- **Routing policy**: `Simple routing`

Click **Create records**

**Record 2: Wildcard for Subdomains (Required if using subdomains)**

**⚠️ Important:** Wildcard `*.sip.yourcompany.com` does NOT match `sip.yourcompany.com` itself!

If you want to support multiple accounts with subdomains like:
- `account1.sip.yourcompany.com`
- `account2.sip.yourcompany.com`
- `customer1.sip.yourcompany.com`

**Record Configuration:**
- **Record name**: `*.sip`
- **Record type**: `A`
- **Value**: Your EC2 public IP (e.g., `13.203.223.245`)
- **TTL**: `300`
- **Routing policy**: `Simple routing`

Click **Create records**

**Summary:**
- ✅ `sip.yourcompany.com` → 13.203.223.245 (base domain)
- ✅ `*.sip.yourcompany.com` → 13.203.223.245 (subdomains like account1.sip.yourcompany.com)

### Option B: Using AWS CLI

```bash
# Set variables
DOMAIN="yourcompany.com"
SUBDOMAIN="sip"
EC2_IP="13.203.223.245"
HOSTED_ZONE_ID="Z1234567890ABC"  # Get from Route53 console

# Create A record for sip.yourcompany.com
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "'$SUBDOMAIN'.'$DOMAIN'",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$EC2_IP'"}]
      }
    }]
  }'

# Create wildcard record for *.sip.yourcompany.com (optional)
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "*.'$SUBDOMAIN'.'$DOMAIN'",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "'$EC2_IP'"}]
      }
    }]
  }'
```

## Step 3: Verify DNS Resolution

After creating the records, verify they work:

```bash
# From your local machine or EC2 instance
dig sip.yourcompany.com
# Should return: sip.yourcompany.com. 300 IN A 13.203.223.245

# Or using nslookup
nslookup sip.yourcompany.com
# Should return: 13.203.223.245

# Or using host
host sip.yourcompany.com
# Should return: sip.yourcompany.com has address 13.203.223.245
```

**Note:** DNS propagation can take a few minutes. Use a low TTL (60-300 seconds) for faster updates.

## Step 4: Configure SIP Realm in Jambonz

1. **Log into webapp**: `http://13.203.223.245:3001`
2. **Go to**: Accounts → Create Account (or edit existing)
3. **In "SIP realm" field**, enter: `sip.yourcompany.com`
4. **Save** the account

## DNS Record Examples

### Example 1: Single SIP Domain

**Domain**: `yourcompany.com`  
**SIP Realm**: `sip.yourcompany.com`

**Route53 Record:**
```
Name: sip.yourcompany.com
Type: A
Value: 13.203.223.245
TTL: 300
```

### Example 2: Multiple Account Subdomains

**Domain**: `yourcompany.com`  
**Root Domain** (in service_providers table): `sip.yourcompany.com`  
**Account SIP Realms**:
- `account1.sip.yourcompany.com`
- `account2.sip.yourcompany.com`

**Route53 Records (BOTH required):**
```
Record 1:
Name: sip.yourcompany.com
Type: A
Value: 13.203.223.245
TTL: 300

Record 2:
Name: *.sip.yourcompany.com
Type: A
Value: 13.203.223.245
TTL: 300
```

**Why both?**
- `sip.yourcompany.com` → Base domain (required)
- `*.sip.yourcompany.com` → Covers subdomains like `account1.sip.yourcompany.com`
- ⚠️ Wildcard does NOT match the base domain!

### Example 3: Using Root Domain

**Domain**: `yourcompany.com`  
**SIP Realm**: `yourcompany.com` (root domain)

**Route53 Record:**
```
Name: yourcompany.com
Type: A
Value: 13.203.223.245
TTL: 300
```

## Using Elastic IP (Recommended)

**Why use Elastic IP?**
- Your EC2 public IP changes when you stop/restart the instance
- Elastic IP stays the same
- DNS records don't need to be updated

**Steps:**

1. **Allocate Elastic IP**:
   ```bash
   aws ec2 allocate-address --domain vpc
   # Note the AllocationId
   ```

2. **Associate with EC2 instance**:
   ```bash
   aws ec2 associate-address \
     --instance-id i-068137d3d519be41f \
     --allocation-id eipalloc-12345678
   ```

3. **Update Route53 record** to point to Elastic IP

4. **Update HOST_IP in Jambonz**:
   ```bash
   cd /opt/jambonz-infrastructure/docker
   # Edit .env file
   HOST_IP=54.123.45.67  # Your Elastic IP
   
   # Restart services
   docker compose down
   docker compose up -d
   ./update-sbc-ip.sh
   ```

## Health Checks (Optional)

You can set up Route53 health checks to automatically failover to a backup instance:

1. **Create Health Check** in Route53
2. **Endpoint**: `http://13.203.223.245:3000/health` (API health endpoint)
3. **Configure DNS failover** routing policy

## Troubleshooting

### DNS Not Resolving

1. **Check TTL**: Lower TTL (60-300) for faster updates
2. **Wait for propagation**: Can take 5-60 minutes
3. **Verify record**: Check Route53 console that record exists
4. **Check nameservers**: Ensure domain uses Route53 nameservers

### SIP Devices Can't Connect

1. **Verify DNS resolution**: `dig sip.yourcompany.com`
2. **Check security group**: Ports 5060/UDP, 5060/TCP must be open
3. **Check HOST_IP**: Must match your EC2 public IP
4. **Check SBC IP**: Run `./update-sbc-ip.sh` in docker directory

### Multiple Accounts with Subdomains

If using subdomains like `account1.sip.yourcompany.com`:
- Use wildcard record: `*.sip.yourcompany.com A → 13.203.223.245`
- Or create individual records for each account

## API and Webapp Access via DNS (Optional)

You can also create DNS records for API and Webapp access:

### API Server (Port 3000)

**Route53 Record:**
```
Name: api.graine.ai (or api.yourcompany.com)
Type: A
Value: 13.203.223.245
TTL: 300
```

**Access:** `http://api.graine.ai:3000` or `https://api.graine.ai:3000` (if using reverse proxy)

**Note:** Port 3000 must be open in Security Group (see Security Group setup below)

### Webapp (Port 3001)

**Route53 Record:**
```
Name: app.graine.ai (or app.yourcompany.com)
Type: A
Value: 13.203.223.245
TTL: 300
```

**Access:** `http://app.graine.ai:3001` or `https://app.graine.ai:3001` (if using reverse proxy)

**Note:** Port 3001 must be open in Security Group

### Using Reverse Proxy (Recommended for Production)

For production, use Nginx/Apache reverse proxy with SSL:

1. **Install Nginx** on EC2 instance
2. **Configure SSL** (Let's Encrypt)
3. **Create DNS records**:
   - `api.graine.ai` → 13.203.223.245
   - `app.graine.ai` → 13.203.223.245
4. **Nginx config**:
   ```nginx
   # API Server
   server {
       listen 80;
       server_name api.graine.ai;
       location / {
           proxy_pass http://localhost:3000;
       }
   }
   
   # Webapp
   server {
       listen 80;
       server_name app.graine.ai;
       location / {
           proxy_pass http://localhost:3001;
       }
   }
   ```
5. **Open only port 80/443** in Security Group (instead of 3000/3001)

## Security Group Configuration (Required for Port Access)

**Route53 DNS alone doesn't open ports!** You must configure AWS Security Group:

### Required Security Group Rules:

| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 3000 | 0.0.0.0/0 | API Server |
| Custom TCP | TCP | 3001 | 0.0.0.0/0 | Webapp |
| Custom UDP | UDP | 5060 | 0.0.0.0/0 | SIP Signaling |
| Custom TCP | TCP | 5060 | 0.0.0.0/0 | SIP Signaling |
| Custom UDP | UDP | 40000-60000 | 0.0.0.0/0 | RTP Media |
| SSH | TCP | 22 | Your IP | Management |

**How to Configure:**

1. **AWS Console**: EC2 → Instances → Your Instance → Security tab → Click Security Group → Edit inbound rules
2. **Add rules** as shown above
3. **Save rules**

**Or using AWS CLI:**
```bash
SG_ID=$(aws ec2 describe-instances --instance-ids i-068137d3d519be41f --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# API Server
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3000 --cidr 0.0.0.0/0

# Webapp
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 3001 --cidr 0.0.0.0/0
```

## Summary

**Quick Setup:**
1. ✅ **Security Group**: Open ports 3000 (API), 3001 (Webapp), 5060 (SIP), 40000-60000 (RTP)
2. ✅ Allocate Elastic IP (recommended)
3. ✅ Create Route53 A record: `*.sip.graine.ai → 13.203.223.245` (for SIP realm)
4. ✅ Create Route53 A record: `api.graine.ai → 13.203.223.245` (optional, for API access)
5. ✅ Create Route53 A record: `app.graine.ai → 13.203.223.245` (optional, for webapp access)
6. ✅ Verify DNS resolution
7. ✅ Set SIP realm in Jambonz webapp: `account1.sip.graine.ai`
8. ✅ Test with SIP device

**Important:**
- **Route53 (DNS)** = Points domain names to IP addresses
- **Security Group** = Opens ports for network access
- **Both are required**: DNS for domain resolution, Security Group for port access
- SIP Realm (DNS) = Domain for device registration (account level)
- SIP Signaling IP = IP address for carrier traffic (system level)

