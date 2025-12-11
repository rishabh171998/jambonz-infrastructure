# Jambonz ALB Setup - Mumbai (ap-south-1)

This configuration creates an Application Load Balancer for Jambonz with separate subdomains:

- **telephony.graine.ai** → API Server (port 3000, HTTPS on 443)
- **sipwebapp.graine.ai** → Webapp (port 3001, HTTPS on 8443)
- **sip.graine.ai** → EC2 Instance (SIP/RTP, direct access - not through ALB)

## Architecture

```
Internet
   |
   ├─ ALB (ap-south-1, Mumbai)
   │   ├─ telephony.graine.ai:443 → API Server (3000)
   │   └─ sipwebapp.graine.ai:8443 → Webapp (3001)
   │
   └─ Direct EC2 (SIP/RTP)
       ├─ sip.graine.ai:5060 (SIP UDP/TCP)
       └─ sip.graine.ai:10000-60000 (RTP UDP)
```

## Prerequisites

1. AWS CLI configured
2. Terraform installed (>= 1.0)
3. VPC in ap-south-1 (Mumbai) with public subnets
4. EC2 instances running Jambonz
5. Route53 hosted zone for graine.ai

## Quick Setup

### Step 1: Request SSL Certificates

```bash
cd terraform/alb
./setup-certificates.sh
```

This will:
- Request certificates for `telephony.graine.ai` and `sipwebapp.graine.ai`
- Show DNS validation records
- Provide certificate ARNs

**Add DNS validation records** to your DNS provider and wait for validation.

### Step 2: Configure Terraform

1. **Copy example file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. **Edit `terraform.tfvars`:**
   ```hcl
   aws_region = "ap-south-1"
   name_prefix = "jambonz"
   vpc_id = "vpc-xxxxxxxxxxxxx"
   
   # Get these from Step 1 after validation
   telephony_certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/xxxxxxxx"
   webapp_certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/yyyyyyyy"
   
   instance_ids = ["i-xxxxxxxxxxxxxxxxx"]
   ```

### Step 3: Deploy ALB

```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Set Up DNS

After ALB is created, get the DNS name:

```bash
terraform output alb_dns_name
```

Then set up DNS records:

```bash
./setup-dns.sh $(terraform output -raw alb_dns_name) [hosted-zone-id]
```

Or manually in Route53:
- **telephony.graine.ai** → ALB (A record, alias)
- **sipwebapp.graine.ai** → ALB (A record, alias)
- **sip.graine.ai** → EC2 instance IP (A record, direct)

## Configuration Details

### Ports

- **80**: HTTP (redirects to HTTPS)
- **443**: HTTPS for telephony.graine.ai (API Server)
- **8443**: HTTPS for sipwebapp.graine.ai (Webapp)
- **5060**: SIP (direct EC2, not ALB)
- **10000-60000**: RTP (direct EC2, not ALB)

### Target Groups

- **API Server**: Port 3000, health check `/api/v1`
- **Webapp**: Port 3001, health check `/`

### Routing

- **Host-based routing** (not path-based):
  - `telephony.graine.ai` → API Server
  - `sipwebapp.graine.ai` → Webapp

## URLs

After setup:

- **API**: `https://telephony.graine.ai/api/v1`
- **Swagger**: `https://telephony.graine.ai/swagger/`
- **Webapp**: `https://sipwebapp.graine.ai`
- **SIP/RTP**: `sip.graine.ai` (direct EC2)

## Testing

### Test API
```bash
curl https://telephony.graine.ai/api/v1/Accounts \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Test Swagger
```bash
open https://telephony.graine.ai/swagger/
```

### Test Webapp
```bash
open https://sipwebapp.graine.ai
```

## Important Notes

### SIP/RTP Traffic

**ALB does NOT support UDP**, so:
- SIP (UDP 5060) → Direct EC2 access via `sip.graine.ai`
- RTP (UDP 10000-60000) → Direct EC2 access via `sip.graine.ai`

The ALB only handles HTTP/HTTPS traffic.

### SSL Certificates

- Certificates must be in **ap-south-1** region
- Use AWS Certificate Manager (ACM)
- DNS validation required
- Certificates must be validated before ALB can use them

### Port 8443 for Webapp

Since ALB can only have one listener per port, we use:
- **443** for telephony.graine.ai (API)
- **8443** for sipwebapp.graine.ai (Webapp)

Alternatively, you can use the same certificate for both domains (wildcard or SAN) and use host-based routing on port 443.

## Troubleshooting

### Certificate Validation

Check certificate status:
```bash
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --region ap-south-1 \
  --query 'Certificate.Status'
```

Should return: `ISSUED`

### Health Checks

Check target health:
```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-south-1
```

### DNS Propagation

Test DNS resolution:
```bash
dig telephony.graine.ai
dig sipwebapp.graine.ai
```

## Cleanup

```bash
terraform destroy
```

**Note**: This will NOT delete SSL certificates or DNS records.

## Cost

ALB pricing in ap-south-1:
- Base: ~₹1,200/month (~$16/month)
- LCU: Based on usage

## Support

For issues:
1. Check certificate status
2. Verify DNS records
3. Check target health
4. Review security groups
