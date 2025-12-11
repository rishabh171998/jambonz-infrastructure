# Domain Routing Configuration

## Current Setup

After ALB deployment, your domains will route as follows:

### HTTPS (Port 443) - Through ALB

- **telephony.graine.ai** → API Server (port 3000)
  - API: `https://telephony.graine.ai/api/v1`
  - Swagger: `https://telephony.graine.ai/swagger/`

- **sipwebapp.graine.ai** → Webapp (port 3001)
  - Webapp: `https://sipwebapp.graine.ai`
  - Internal pages: `https://sipwebapp.graine.ai/internal/accounts`

### Direct EC2 Access (SIP/RTP)

- **sip.graine.ai** → EC2 Instance (direct IP)
  - SIP UDP: `sip.graine.ai:5060`
  - SIP TCP: `sip.graine.ai:5060`
  - RTP UDP: `sip.graine.ai:10000-60000`

## DNS Configuration

### Route53 Records

1. **telephony.graine.ai** (A record, alias to ALB)
   - Type: A
   - Alias: Yes
   - Target: ALB DNS name
   - Zone ID: ALB zone ID

2. **sipwebapp.graine.ai** (A record, alias to ALB)
   - Type: A
   - Alias: Yes
   - Target: ALB DNS name
   - Zone ID: ALB zone ID

3. **sip.graine.ai** (A record, direct IP)
   - Type: A
   - Alias: No
   - Value: EC2 instance public IP

## SSL Certificates

Both certificates must be:
- In **ap-south-1** (Mumbai) region
- Validated (status: ISSUED)
- Requested via ACM

### Option 1: Separate Certificates

- `telephony.graine.ai` certificate
- `sipwebapp.graine.ai` certificate

### Option 2: Wildcard Certificate (Recommended)

- `*.graine.ai` certificate (covers both domains)
- Use same ARN for both `telephony_certificate_arn` and `webapp_certificate_arn`

## Testing URLs

### API
```bash
curl https://telephony.graine.ai/api/v1/Accounts \
  -H "Authorization: Bearer YOUR_TOKEN"
```

### Swagger
```bash
open https://telephony.graine.ai/swagger/
```

### Webapp
```bash
open https://sipwebapp.graine.ai
open https://sipwebapp.graine.ai/internal/accounts
```

## Migration from Current Setup

Currently you're accessing:
- `http://sip.graine.ai:3001/internal/accounts`

After ALB setup:
- `https://sipwebapp.graine.ai/internal/accounts`

**No changes needed** to the webapp code - it will work the same, just with HTTPS and a different domain.

## Troubleshooting

### Webapp not loading

1. **Check DNS:**
   ```bash
   dig sipwebapp.graine.ai
   ```
   Should resolve to ALB DNS name

2. **Check target health:**
   ```bash
   aws elbv2 describe-target-health \
     --target-group-arn <webapp-target-group-arn> \
     --region ap-south-1
   ```

3. **Check security groups:**
   - ALB security group allows 443 from 0.0.0.0/0
   - EC2 security group allows 3001 from ALB security group

### Certificate issues

If using separate certificates, ensure both are validated:
```bash
aws acm describe-certificate \
  --certificate-arn <cert-arn> \
  --region ap-south-1 \
  --query 'Certificate.Status'
```

Both should return: `ISSUED`

