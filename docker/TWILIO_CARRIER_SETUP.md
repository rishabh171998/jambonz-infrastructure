# Configuring Twilio as a Carrier in Jambonz

This guide explains how to configure Twilio Elastic SIP Trunking as a carrier in your Jambonz Docker setup.

## Prerequisites

✅ **Docker setup is ready** - All services running  
✅ **SIP Signaling IP configured** - Shows `13.203.223.245:5060` in webapp  
✅ **Security Group configured** - Ports 5060, 3000, 3001, 40000-60000 open  
✅ **DNS configured** - `sip.graine.ai` resolves to `13.203.223.245`  

## Step 1: Configure Twilio Elastic SIP Trunk

### In Twilio Console:

1. **Go to**: Elastic SIP Trunking → Trunks → Create New Trunk

2. **General Settings**:
   - Friendly Name: `Jambonz Production` (or your preferred name)
   - Call Recording: Configure as needed
   - Secure Trunking: Optional (TLS/SRTP)

3. **Termination Settings** (Outbound from Jambonz to Twilio):
   - **Termination URI**: `your-trunk-name.pstn.twilio.com`
     - Example: `jambonz-prod.pstn.twilio.com`
   - **Authentication**: 
     - Create IP Access Control List with your EC2 IP: `13.203.223.245`
     - OR Create Credential List (username/password)
     - **Recommended**: Use both for security

4. **Origination Settings** (Inbound from Twilio to Jambonz):
   - **Origination SIP URI**: 
     - For UDP/TCP: `sip:graineone.sip.graine.ai` or `sip:13.203.223.245`
     - For TLS: `sip:graineone.sip.graine.ai:5061;transport=tls`
   - **Priority**: `10`
   - **Weight**: `10`
   
   **Note**: Using `sip:graineone.sip.graine.ai` requires DNS record `graineone.sip.graine.ai` pointing to `13.203.223.245`. The wildcard `*.sip.graine.ai` should cover this.

5. **Numbers**:
   - Buy or associate Twilio phone numbers with this trunk

## Step 2: Configure Carrier in Jambonz Webapp

### In Jambonz Webapp (http://13.203.223.245:3001):

1. **Go to**: Carriers → Add a carrier

2. **Carrier Configuration**:
   - **Carrier name**: `Twilio` (or your preferred name)
   - **Active**: ✅ Enabled
   - **Voice**: ✅ Enabled
   - **SMS**: ✅ Enabled (if using SMS)

3. **SIP Gateways** (Termination - Outbound):
   - **Network address**: `your-trunk-name.pstn.twilio.com`
     - Example: `jambonz-prod.pstn.twilio.com`
   - **Port**: `5060` (or `5061` if using TLS)
   - **Netmask**: `32`
   - **Inbound**: ✅ Enabled
   - **Outbound**: ✅ Enabled

   **For TLS**:
   - Network address: `your-trunk-name.pstn.twilio.com`
   - Port: `5061`
   - Netmask: `32`

4. **Outbound Authentication** (if using credentials):
   - **Username**: Your Twilio credential username
   - **Password**: Your Twilio credential password

5. **E.164 syntax**: ✅ Enabled (required by Twilio)

6. **Click**: Save

## Step 3: Configure Security Group for TLS (Port 5061)

**If using TLS/SRTP**, you need to open port 5061:

### In AWS Console:

1. **Go to**: EC2 → Instances → Your Instance → Security tab
2. **Click**: Security group name
3. **Click**: Edit inbound rules
4. **Add rule**:
   - Type: `Custom TCP`
   - Port: `5061`
   - Source: `0.0.0.0/0` (or restrict to Twilio IPs)
   - Description: `SIP TLS`
5. **Save rules**

### Using AWS CLI:

```bash
SG_ID=$(aws ec2 describe-instances --instance-ids i-068137d3d519be41f --query 'Reservations[0].Instances[0].SecurityGroups[0].GroupId' --output text)

# Add SIP TLS port
aws ec2 authorize-security-group-ingress --group-id $SG_ID --protocol tcp --port 5061 --cidr 0.0.0.0/0
```

## Step 4: Configure Twilio IP Whitelisting

### In Twilio Console:

1. **Go to**: Elastic SIP Trunking → IP Access Control Lists
2. **Create ACL** or edit existing
3. **Add IP**: `13.203.223.245` (your EC2 public IP)
4. **Associate with your Trunk**

**Important**: Twilio will reject SIP traffic from IPs not in the ACL (if ACL is configured).

## Step 4: Verify DNS for Origination URI

**If using `sip:graineone.sip.graine.ai`**, verify DNS resolution:

```bash
# Test DNS resolution
dig graineone.sip.graine.ai

# Should return: graineone.sip.graine.ai. 300 IN A 13.203.223.245
```

**Note**: The wildcard record `*.sip.graine.ai` should cover `graineone.sip.graine.ai`. If it doesn't resolve, wait a few minutes for DNS propagation or create a specific record.

## Step 5: Test the Connection

### Test Outbound (Jambonz → Twilio):

1. Make a call from your SIP device registered to Jambonz
2. Dial a phone number (E.164 format: `+12125551234`)
3. The call should route through Twilio to the PSTN

### Test Inbound (Twilio → Jambonz):

1. Call your Twilio phone number
2. The call should be delivered to Jambonz at `sip:13.203.223.245` or `sip:sip.graine.ai`

## Important Configuration Details

### SIP URI Formats

**Twilio Termination URI** (for Jambonz outbound):
```
sip:+12125551234@your-trunk-name.pstn.twilio.com
```

**Jambonz Origination URI** (for Twilio inbound):
```
sip:graineone.sip.graine.ai
# OR
sip:13.203.223.245
# OR for TLS
sip:graineone.sip.graine.ai:5061;transport=tls
```

### E.164 Format

**Critical**: Twilio requires E.164 format (with `+` prefix):
- ✅ Correct: `+12125551234`
- ❌ Wrong: `12125551234` or `(212) 555-1234`

### Codecs

Twilio supports:
- G.711 (PCMU/PCMA) - Default
- G.729
- G.722
- Opus

Configure in Jambonz application settings if needed.

### RTP Media

Twilio will send RTP to your EC2 IP. Ensure:
- Security Group allows UDP 40000-60000
- RTPEngine is running and configured with `HOST_IP=13.203.223.245`

## Troubleshooting

### Calls Not Connecting

1. **Check Security Group**: Ensure ports 5060/UDP, 5060/TCP are open
2. **Check Twilio ACL**: Verify `13.203.223.245` is whitelisted
3. **Check SIP Logs**: 
   ```bash
   docker compose logs drachtio-sbc
   docker compose logs sbc-outbound
   ```
4. **Check Twilio Console**: View call logs in Twilio dashboard

### One-Way Audio

1. **Check RTP Ports**: Security Group must allow UDP 40000-60000
2. **Check HOST_IP**: Must be set to `13.203.223.245` in `.env`
3. **Check RTPEngine**: 
   ```bash
   docker compose logs rtpengine
   ```

### Authentication Failures

1. **Check Credentials**: Verify username/password in Jambonz carrier config
2. **Check Twilio Credential List**: Ensure credentials match
3. **Check IP ACL**: If using IP ACL, ensure IP is whitelisted

## Twilio Edge Locations (Optional)

For better latency, you can use localized termination URIs:

- `your-trunk-name.pstn.ashburn.twilio.com` (US East)
- `your-trunk-name.pstn.umatilla.twilio.com` (US West)
- `your-trunk-name.pstn.dublin.twilio.com` (Europe)
- `your-trunk-name.pstn.singapore.twilio.com` (Asia Pacific)

Configure multiple gateways in Jambonz with different priorities for failover.

## Summary

**What You Need from Twilio:**
- Termination URI: `your-trunk-name.pstn.twilio.com`
- Origination URI: `sip:13.203.223.245` (your EC2 IP)
- IP ACL: Add `13.203.223.245` to whitelist
- Credentials: Username/password (if using credential auth)

**What Twilio Needs from You:**
- SIP Signaling IP: `13.203.223.245:5060` (already configured ✅)
- Origination URI: `sip:13.203.223.245` or `sip:sip.graine.ai`
- RTP Media: UDP ports 40000-60000 open

Your Docker setup is ready! Just configure the carrier in the webapp and Twilio console.

