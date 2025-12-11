# ALB Setup Guide for Jambonz

## Overview

This guide helps you set up an Application Load Balancer (ALB) for Jambonz to:
- Load balance HTTP/HTTPS traffic
- Provide SSL termination
- Route API and webapp traffic
- Enable high availability

## Important: SIP/RTP Traffic

**ALB does NOT support UDP**, which is required for:
- SIP signaling (UDP 5060)
- RTP media (UDP 10000-60000)

**For SIP/RTP, you have two options:**

1. **Keep direct EC2 access** (current setup) - SIP/RTP goes directly to EC2
2. **Use Network Load Balancer (NLB)** - Separate NLB for SIP/RTP traffic

This ALB setup is for **HTTP/HTTPS only** (API, Webapp, Swagger).

## Architecture

```
Internet
   |
   ├─ ALB (HTTP/HTTPS)
   │   ├─ /api/* → API Server (3000)
   │   ├─ /swagger* → API Server (3000)
   │   └─ /* → Webapp (3001)
   │
   └─ Direct EC2 (SIP/RTP)
       ├─ SIP UDP 5060
       ├─ SIP TCP 5060
       └─ RTP UDP 10000-60000
```

## Prerequisites

1. AWS account with appropriate permissions
2. VPC with public subnets
3. EC2 instances running Jambonz
4. Terraform installed (>= 1.0)
5. SSL certificate in ACM (optional, for HTTPS)

## Quick Setup

### Step 1: Get Your VPC ID

```bash
aws ec2 describe-vpcs --query "Vpcs[*].[VpcId,Tags[?Key=='Name'].Value|[0]]" --output table
```

### Step 2: Get Your Instance IDs

```bash
aws ec2 describe-instances --filters "Name=tag:Name,Values=jambonz*" --query "Reservations[*].Instances[*].[InstanceId,PrivateIpAddress]" --output table
```

### Step 3: Configure Terraform

1. **Navigate to ALB directory:**
   ```bash
   cd terraform/alb
   ```

2. **Copy example file:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

3. **Edit `terraform.tfvars`:**
   ```hcl
   aws_region = "us-east-1"
   name_prefix = "jambonz"
   vpc_id = "vpc-xxxxxxxxxxxxx"
   instance_ids = ["i-xxxxxxxxxxxxxxxxx"]
   
   # Optional: SSL certificate ARN
   # ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx"
   ```

### Step 4: Deploy ALB

```bash
terraform init
terraform plan
terraform apply
```

### Step 5: Get ALB DNS Name

```bash
terraform output alb_dns_name
```

## SSL Certificate Setup (Optional)

### Option 1: Request New Certificate

1. **Request certificate in ACM:**
   ```bash
   aws acm request-certificate \
     --domain-name sip.graine.ai \
     --validation-method DNS \
     --region us-east-1
   ```

2. **Add DNS validation records** to your DNS provider

3. **Wait for validation** (can take a few minutes)

4. **Get certificate ARN:**
   ```bash
   aws acm list-certificates --region us-east-1
   ```

5. **Update `terraform.tfvars`:**
   ```hcl
   ssl_certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx"
   ```

6. **Re-apply Terraform:**
   ```bash
   terraform apply
   ```

### Option 2: Import Existing Certificate

```bash
aws acm import-certificate \
  --certificate fileb://certificate.pem \
  --private-key fileb://private-key.pem \
  --certificate-chain fileb://chain.pem \
  --region us-east-1
```

## DNS Configuration

After ALB is created, update your DNS:

1. **Get ALB DNS name:**
   ```bash
   terraform output alb_dns_name
   ```

2. **Create/Update DNS A record:**
   - **Type**: A (Alias)
   - **Name**: `sip.graine.ai` (or your domain)
   - **Alias Target**: ALB DNS name
   - **Alias Hosted Zone**: ALB zone ID (from terraform output)

Or use Route 53:

```bash
aws route53 change-resource-record-sets \
  --hosted-zone-id Z1234567890ABC \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "sip.graine.ai",
        "Type": "A",
        "AliasTarget": {
          "HostedZoneId": "Z35SXDOTRQ7X7K",
          "DNSName": "alb-123456789.us-east-1.elb.amazonaws.com",
          "EvaluateTargetHealth": true
        }
      }
    }]
  }'
```

## Security Groups

### ALB Security Group

The ALB security group allows:
- HTTP (80) from 0.0.0.0/0
- HTTPS (443) from 0.0.0.0/0

**For production, restrict to specific IPs:**
```hcl
ingress {
  from_port   = 443
  to_port     = 443
  protocol    = "tcp"
  cidr_blocks = ["YOUR_IP/32"]  # Your office IP
  description = "HTTPS"
}
```

### EC2 Security Group

Your EC2 security group must allow:
- **From ALB**: HTTP (3000, 3001) from ALB security group
- **From Internet**: SIP (5060 UDP/TCP) and RTP (10000-60000 UDP)

## Health Checks

- **API Server**: Checks `/api/v1` (expects 200, 301, or 302)
- **Webapp**: Checks `/` (expects 200, 301, or 302)

If health checks fail:
1. Verify services are running
2. Check security groups
3. Verify health check path

## Testing

### Test API
```bash
curl https://sip.graine.ai/api/v1/Accounts \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Test Swagger
```bash
open https://sip.graine.ai/swagger/
```

### Test Webapp
```bash
open https://sip.graine.ai
```

## Troubleshooting

### 502 Bad Gateway

1. **Check target health:**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <target-group-arn>
   ```

2. **Verify instances are registered:**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <target-group-arn> \
     --query "TargetHealthDescriptions[*].[Target.Id,TargetHealth.State]"
   ```

3. **Check security groups** allow traffic from ALB

### Health Checks Failing

1. **Test health check endpoint manually:**
   ```bash
   curl http://<instance-ip>:3000/api/v1
   curl http://<instance-ip>:3001/
   ```

2. **Check application logs:**
   ```bash
   sudo docker compose logs api-server
   sudo docker compose logs webapp
   ```

### SSL Certificate Issues

1. **Verify certificate is validated:**
   ```bash
   aws acm describe-certificate \
     --certificate-arn <cert-arn> \
     --query "Certificate.Status"
   ```

2. **Check certificate is in correct region** (must match ALB region)

## Cost Considerations

ALB pricing:
- **Base**: ~$0.0225/hour (~$16/month)
- **LCU**: Based on usage (requests, data processed)

For cost savings:
- Use single ALB for multiple services
- Consider CloudFront for static content
- Use NLB for SIP/RTP (cheaper, but no HTTP features)

## Cleanup

To remove ALB:
```bash
terraform destroy
```

**Note**: This will delete the ALB and target groups, but NOT the EC2 instances.

## Next Steps

1. ✅ ALB created and configured
2. ✅ DNS updated to point to ALB
3. ✅ SSL certificate configured (if using HTTPS)
4. ✅ Health checks passing
5. ✅ Test API, Swagger, and Webapp access

## Support

For issues:
1. Check Terraform outputs: `terraform output`
2. Check ALB logs (if enabled)
3. Check target health status
4. Review security group rules

