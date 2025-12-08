# AWS Security Group Configuration for Docker-based Jambonz

## Required Security Group Rules

### Inbound Rules

#### SIP Signaling (Required)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 5060 | `0.0.0.0/0` or specific CIDR | SIP signaling (UDP) |
| Custom TCP | TCP | 5060 | `0.0.0.0/0` or specific CIDR | SIP signaling (TCP) |
| Custom TCP | TCP | 5061 | `0.0.0.0/0` or specific CIDR | SIP over TLS (required if using TLS) |
| Custom TCP | TCP | 8443 | `0.0.0.0/0` or specific CIDR | SIP over WSS (optional) |

#### RTP Media (Required)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom UDP | UDP | 40000-60000 | `0.0.0.0/0` or specific CIDR | RTP media streams |

**Note:** Your docker-compose.yaml uses `40000-40100`, but you may want to expand this range for production.

#### HTTP/HTTPS (Required for Web Access)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| HTTP | TCP | 80 | `0.0.0.0/0` or specific CIDR | HTTP (if using nginx) |
| HTTPS | TCP | 443 | `0.0.0.0/0` or specific CIDR | HTTPS (if using nginx) |
| Custom TCP | TCP | 3000 | `0.0.0.0/0` or specific CIDR | API Server (if not behind nginx) |
| Custom TCP | TCP | 3001 | `0.0.0.0/0` or specific CIDR | Webapp (if not behind nginx) |

#### Management (Required)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| SSH | TCP | 22 | Your IP or specific CIDR | SSH access |

#### Monitoring (Optional)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 8086 | `0.0.0.0/0` or VPC CIDR | InfluxDB |
| Custom TCP | TCP | 9080 | `0.0.0.0/0` or specific CIDR | Homer |
| Custom TCP | TCP | 3000 | `0.0.0.0/0` or specific CIDR | Grafana |

#### FreeSWITCH Management (Optional)
| Type | Protocol | Port Range | Source | Description |
|------|----------|------------|--------|-------------|
| Custom TCP | TCP | 8022 | VPC CIDR or specific IP | FreeSWITCH Event Socket |

### Outbound Rules

| Type | Protocol | Port Range | Destination | Description |
|------|----------|------------|-------------|-------------|
| All traffic | All | All | `0.0.0.0/0` | Allow all outbound traffic |

## AWS Console Setup Steps

### 1. Create Security Group

1. Go to **EC2 Console** → **Security Groups**
2. Click **Create Security Group**
3. Name: `jambonz-docker-sg`
4. Description: `Security group for Jambonz Docker deployment`
5. VPC: Select your VPC

### 2. Add Inbound Rules

Click **Add Rule** for each rule below:

**SIP Rules:**
- Type: `Custom UDP`, Port: `5060`, Source: `0.0.0.0/0` (or your carrier IPs)
- Type: `Custom TCP`, Port: `5060`, Source: `0.0.0.0/0` (or your carrier IPs)
- Type: `Custom TCP`, Port: `5061`, Source: `0.0.0.0/0` (required if using TLS/SRTP)
- Type: `Custom TCP`, Port: `8443`, Source: `0.0.0.0/0` (optional, for WSS)

**RTP Rules:**
- Type: `Custom UDP`, Port Range: `40000-60000`, Source: `0.0.0.0/0`

**HTTP/HTTPS Rules:**
- Type: `HTTP`, Port: `80`, Source: `0.0.0.0/0` (or specific CIDR)
- Type: `HTTPS`, Port: `443`, Source: `0.0.0.0/0` (or specific CIDR)
- Type: `Custom TCP`, Port: `3000`, Source: `0.0.0.0/0` (if API not behind nginx)
- Type: `Custom TCP`, Port: `3001`, Source: `0.0.0.0/0` (if webapp not behind nginx)

**SSH:**
- Type: `SSH`, Port: `22`, Source: `YOUR_IP/32` (restrict to your IP)

**Optional Monitoring:**
- Type: `Custom TCP`, Port: `8086`, Source: VPC CIDR (InfluxDB)
- Type: `Custom TCP`, Port: `9080`, Source: `0.0.0.0/0` (Homer)
- Type: `Custom TCP`, Port: `3000`, Source: `0.0.0.0/0` (Grafana)

### 3. Add Outbound Rules

- Type: `All traffic`, Destination: `0.0.0.0/0`

### 4. Attach to EC2 Instance

1. Go to your EC2 instance
2. Click **Actions** → **Security** → **Change Security Groups**
3. Select `jambonz-docker-sg`
4. Click **Save**

## AWS CLI Setup

```bash
# Create security group
aws ec2 create-security-group \
  --group-name jambonz-docker-sg \
  --description "Security group for Jambonz Docker deployment" \
  --vpc-id vpc-xxxxxxxxx

# Save the GroupId from output, then add rules:

GROUP_ID="sg-xxxxxxxxx"

# SIP UDP
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol udp \
  --port 5060 \
  --cidr 0.0.0.0/0

# SIP TCP
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 5060 \
  --cidr 0.0.0.0/0

# SIP TLS (required if using TLS/SRTP)
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 5061 \
  --cidr 0.0.0.0/0

# RTP UDP Range
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol udp \
  --port 40000 \
  --cidr 0.0.0.0/0 \
  --ip-permissions IpProtocol=udp,FromPort=40000,ToPort=60000,IpRanges=[{CidrIp=0.0.0.0/0}]

# HTTP
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0

# HTTPS
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 443 \
  --cidr 0.0.0.0/0

# SSH (restrict to your IP)
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32

# API Server (if not behind nginx)
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 3000 \
  --cidr 0.0.0.0/0

# Webapp (if not behind nginx)
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 3001 \
  --cidr 0.0.0.0/0
```

## Terraform Example

```hcl
resource "aws_security_group" "jambonz_docker" {
  name        = "jambonz-docker-sg"
  description = "Security group for Jambonz Docker deployment"
  vpc_id      = var.vpc_id

  # SIP UDP
  ingress {
    description = "SIP UDP"
    from_port   = 5060
    to_port     = 5060
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SIP TCP
  ingress {
    description = "SIP TCP"
    from_port   = 5060
    to_port     = 5060
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SIP TLS (required if using TLS/SRTP)
  ingress {
    description = "SIP TLS"
    from_port   = 5061
    to_port     = 5061
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # RTP UDP Range
  ingress {
    description = "RTP Media"
    from_port   = 40000
    to_port     = 60000
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS
  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["YOUR_IP/32"]  # Restrict to your IP
  }

  # API Server
  ingress {
    description = "API Server"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Webapp
  ingress {
    description = "Webapp"
    from_port   = 3001
    to_port     = 3001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "jambonz-docker-sg"
  }
}
```

## Additional AWS Considerations

### 1. Elastic IP (Recommended)
- Allocate an Elastic IP for your EC2 instance
- This ensures your SIP contact address doesn't change
- Required for carrier trunking

### 2. Network ACLs (Optional)
- Additional layer of security at subnet level
- Usually not needed if security groups are properly configured

### 3. IAM Role (Optional but Recommended)
- Create IAM role for CloudWatch Logs (if using CloudWatch)
- Attach to EC2 instance

### 4. EC2 Instance Requirements
- **Instance Type:** Minimum `t3.medium` for testing, `c5.xlarge` or larger for production
- **Storage:** Minimum 50GB EBS volume (100GB recommended)
- **Network:** Enhanced networking recommended for RTP performance

### 5. Docker Prerequisites on EC2
- Docker installed
- Docker Compose installed
- Ports mapped correctly in docker-compose.yaml
- `HOST_IP` environment variable set to EC2 instance's public IP

## Testing Your Setup

After configuring security groups:

```bash
# Test SIP port
nc -uv YOUR_EC2_IP 5060

# Test RTP port
nc -uv YOUR_EC2_IP 40000

# Test HTTP
curl http://YOUR_EC2_IP:3000/health

# Test Webapp
curl http://YOUR_EC2_IP:3001
```

## Security Best Practices

1. **Restrict SSH Access:** Only allow SSH from your IP (`YOUR_IP/32`)
2. **Restrict HTTP/HTTPS:** If possible, restrict to specific IPs or use VPN
3. **Use WAF:** Consider AWS WAF for HTTP/HTTPS traffic
4. **Enable VPC Flow Logs:** Monitor network traffic
5. **Use Private Subnet:** Consider placing in private subnet with NAT Gateway
6. **Regular Updates:** Keep Docker images and EC2 instance updated

## Notes

- The RTP port range (40000-60000) is large but necessary for handling multiple concurrent calls
- Consider using AWS Application Load Balancer (ALB) for HTTP/HTTPS traffic instead of direct exposure
- For production, consider restricting SIP and RTP to known carrier IPs instead of `0.0.0.0/0`

