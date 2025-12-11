# Quick Start Guide - Jambonz ALB Setup

## Overview

This setup creates an ALB in **Mumbai (ap-south-1)** with:
- **telephony.graine.ai** → API Server (HTTPS on port 443)
- **sipwebapp.graine.ai** → Webapp (HTTPS on port 8443, or 443 if using wildcard cert)
- **sip.graine.ai** → EC2 Instance (SIP/RTP, direct access)

## Step-by-Step Setup

### Step 1: Request SSL Certificates

```bash
cd terraform/alb
./setup-certificates.sh
```

**Add DNS validation records** to your DNS provider and wait for validation.

**Check validation status:**
```bash
aws acm list-certificates --region ap-south-1 --query "CertificateSummaryList[*].[DomainName,CertificateArn,Status]"
```

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
   
   # Your EC2 instance ID
   instance_ids = ["i-xxxxxxxxxxxxxxxxx"]
   ```

### Step 3: Deploy ALB

```bash
terraform init
terraform plan
terraform apply
```

### Step 4: Set Up DNS

After ALB is created:

```bash
# Get ALB DNS name
terraform output alb_dns_name

# Set up DNS records
./setup-dns.sh $(terraform output -raw alb_dns_name)
```

**Or manually in Route53:**
- **telephony.graine.ai** → ALB (A record, alias to ALB)
- **sipwebapp.graine.ai** → ALB (A record, alias to ALB)
- **sip.graine.ai** → EC2 instance IP (A record, direct IP)

## URLs After Setup

- **API**: `https://telephony.graine.ai/api/v1`
- **Swagger**: `https://telephony.graine.ai/swagger/`
- **Webapp**: `https://sipwebapp.graine.ai:8443` (or `https://sipwebapp.graine.ai` if using wildcard cert on 443)
- **SIP/RTP**: `sip.graine.ai` (direct EC2)

## Using Wildcard Certificate (Optional)

If you have a wildcard certificate `*.graine.ai`, you can use it for both domains:

1. **Request wildcard certificate:**
   ```bash
   aws acm request-certificate \
     --domain-name "*.graine.ai" \
     --validation-method DNS \
     --region ap-south-1
   ```

2. **Update `terraform.tfvars`:**
   ```hcl
   telephony_certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/wildcard-arn"
   webapp_certificate_arn = "arn:aws:acm:ap-south-1:123456789012:certificate/wildcard-arn"
   ```

3. **Modify `jambonz-alb.tf`** to use single listener on 443 with host-based routing (see README.md for details)

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
open https://sipwebapp.graine.ai:8443
# Or if using wildcard cert:
open https://sipwebapp.graine.ai
```

## Troubleshooting

### Certificate Not Validated
```bash
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --region ap-south-1 \
  --query 'Certificate.Status'
```

Should return: `ISSUED`

### Health Checks Failing
```bash
aws elbv2 describe-target-health \
  --target-group-arn <target-group-arn> \
  --region ap-south-1
```

### DNS Not Resolving
```bash
dig telephony.graine.ai
dig sipwebapp.graine.ai
```

## Cleanup

```bash
terraform destroy
```

