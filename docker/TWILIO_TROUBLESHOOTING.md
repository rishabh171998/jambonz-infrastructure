# Troubleshooting Twilio Connection Issues

## Error 32011: Request Timeout

This error means Twilio cannot reach your Jambonz SIP endpoint. Follow these steps:

## Step 1: Verify HOST_IP Environment Variable

**Critical**: The `HOST_IP` environment variable must be set to your EC2 public IP.

```bash
# On your EC2 instance, check if HOST_IP is set:
echo $HOST_IP

# If not set or incorrect, set it:
export HOST_IP=13.203.223.245

# Add to your shell profile for persistence:
echo "export HOST_IP=13.203.223.245" >> ~/.bashrc
source ~/.bashrc

# Restart Docker Compose with the correct HOST_IP:
cd /opt/jambonz-infrastructure/docker
docker compose down
HOST_IP=13.203.223.245 docker compose up -d
```

## Step 2: Verify Docker Services Are Running

```bash
cd /opt/jambonz-infrastructure/docker
docker compose ps

# All services should show "Up" status, especially:
# - drachtio-sbc
# - sbc-inbound
# - sbc-outbound
```

## Step 3: Check if drachtio-sbc is Listening on Port 5060

```bash
# Check if port 5060 is listening:
sudo netstat -tulpn | grep 5060
# OR
sudo ss -tulpn | grep 5060

# Should show:
# tcp  0  0 0.0.0.0:5060  0.0.0.0:*  LISTEN  <docker-pid>
# udp  0  0 0.0.0.0:5060  0.0.0.0:*  <docker-pid>
```

## Step 4: Check Docker Container Logs

```bash
# Check drachtio-sbc logs:
docker compose logs drachtio-sbc | tail -50

# Look for:
# - "listening on tcp/0.0.0.0:5060"
# - "listening on udp/0.0.0.0:5060"
# - "contact: sip:13.203.223.245;transport=udp,tcp"
# - "external-ip: 13.203.223.245"

# Check sbc-inbound logs:
docker compose logs sbc-inbound | tail -50

# Check sbc-outbound logs:
docker compose logs sbc-outbound | tail -50
```

## Step 5: Verify Security Group Rules

Your security group should allow:
- **Port 5060 TCP/UDP** from `0.0.0.0/0` (or Twilio IP ranges)
- **Port 5061 TCP** from `0.0.0.0/0` (if using TLS)

**Twilio IP Ranges** (recommended to restrict):
- See: https://www.twilio.com/docs/voice/sip/ip-addresses-trunking
- Or allow `0.0.0.0/0` for testing (less secure)

## Step 6: Test SIP Connectivity from External Network

```bash
# From your local machine or another server, test if port 5060 is reachable:
telnet 13.203.223.245 5060
# OR
nc -zv 13.203.223.245 5060

# Should connect successfully
```

## Step 7: Verify SIP Realm Configuration

The SIP realm in your Jambonz account must match what Twilio is sending.

1. **In Jambonz Webapp** → Accounts → Your Account:
   - **SIP Realm**: Should be `graineone.sip.graine.ai` (or `sip.graine.ai`)

2. **In Twilio Console** → Elastic SIP Trunking → Origination:
   - **Origination SIP URI**: `sip:graineone.sip.graine.ai`
   - Should NOT include port unless using non-standard port

## Step 8: Check DNS Resolution

```bash
# From your EC2 instance:
dig graineone.sip.graine.ai

# Should resolve to: 13.203.223.245

# From external network (your local machine):
dig graineone.sip.graine.ai

# Should also resolve to: 13.203.223.245
```

## Step 9: Verify Twilio Origination URI Format

**In Twilio Console** → Elastic SIP Trunking → Your Trunk → Origination:

**Correct formats:**
- ✅ `sip:graineone.sip.graine.ai` (recommended - uses DNS)
- ✅ `sip:13.203.223.245` (works but less flexible)
- ✅ `sip:graineone.sip.graine.ai:5060` (explicit port)

**Incorrect formats:**
- ❌ `sip:+15707744873@graineone.sip.graine.ai` (includes phone number)
- ❌ `sip:graineone.sip.graine.ai:5061` (unless TLS is configured)

## Step 10: Check Firewall Rules on EC2 Instance

```bash
# Check iptables rules:
sudo iptables -L -n -v

# Check UFW (if enabled):
sudo ufw status

# If UFW is blocking, allow ports:
sudo ufw allow 5060/tcp
sudo ufw allow 5060/udp
sudo ufw allow 5061/tcp
```

## Step 11: Verify drachtio-sbc Configuration

```bash
# Check drachtio-sbc container environment:
docker compose exec drachtio-sbc env | grep HOST_IP

# Should show: HOST_IP=13.203.223.245

# Check drachtio-sbc process:
docker compose exec drachtio-sbc ps aux | grep drachtio

# Check drachtio logs for contact/external-ip:
docker compose logs drachtio-sbc | grep -i "contact\|external"
```

## Step 12: Test with SIPp or sipcmd (Optional)

If you have `sipp` or `sipcmd` installed, you can test SIP connectivity:

```bash
# Install sipcmd (if not installed):
sudo apt-get install sipcmd

# Test SIP registration (replace with your credentials):
sipcmd -P sip -u <username> -c <password> -w graineone.sip.graine.ai -x "r"
```

## Common Issues and Solutions

### Issue 1: "Cannot assign requested address" Error
**Symptom**: `nta: bind(13.203.223.245:5060): Cannot assign requested address`

**Solution**: This happens when drachtio tries to bind to the public IP directly. The fix is to use `sip:*` for contact (binds to all interfaces) and use `--external-ip` for the public IP. This is already fixed in the latest docker-compose.yaml. Restart: `docker compose restart drachtio-sbc`

### Issue 2: HOST_IP Not Set
**Symptom**: drachtio-sbc shows `contact: sip:127.0.0.1` or `contact: sip:172.10.0.10`

**Solution**: Set `HOST_IP=13.203.223.245` and restart Docker Compose

### Issue 2: Port 5060 Not Listening
**Symptom**: `netstat` shows nothing on port 5060

**Solution**: 
- Check if drachtio-sbc container is running: `docker compose ps drachtio-sbc`
- Check logs: `docker compose logs drachtio-sbc`
- Restart: `docker compose restart drachtio-sbc`

### Issue 3: Security Group Blocking
**Symptom**: External `telnet` to port 5060 fails

**Solution**: 
- Verify security group allows port 5060 from `0.0.0.0/0` or Twilio IPs
- Check EC2 instance firewall (iptables/ufw)

### Issue 4: Wrong SIP Realm
**Symptom**: Calls reach server but are rejected

**Solution**: 
- Verify SIP realm in Jambonz account matches domain in Twilio URI
- Check `graineone.sip.graine.ai` vs `sip.graine.ai`

### Issue 5: DNS Not Resolving
**Symptom**: `dig graineone.sip.graine.ai` returns NXDOMAIN

**Solution**: 
- Verify Route53 A record exists for `graineone.sip.graine.ai`
- Verify wildcard record `*.sip.graine.ai` exists
- Wait for DNS propagation (can take up to 5 minutes)

## Quick Diagnostic Script

Run this on your EC2 instance:

```bash
#!/bin/bash
echo "=== Jambonz Twilio Connection Diagnostics ==="
echo ""
echo "1. HOST_IP Environment Variable:"
echo "   HOST_IP=${HOST_IP:-NOT SET}"
echo ""
echo "2. Docker Services Status:"
cd /opt/jambonz-infrastructure/docker && docker compose ps | grep -E "drachtio-sbc|sbc-inbound|sbc-outbound"
echo ""
echo "3. Port 5060 Listening:"
sudo netstat -tulpn | grep 5060 || echo "   ❌ Port 5060 not listening"
echo ""
echo "4. DNS Resolution:"
dig +short graineone.sip.graine.ai || echo "   ❌ DNS not resolving"
echo ""
echo "5. drachtio-sbc Logs (last 10 lines):"
docker compose logs --tail=10 drachtio-sbc
echo ""
echo "6. Security Group Check:"
echo "   Please verify in AWS Console that port 5060 TCP/UDP is open"
```

## Next Steps

If all checks pass but Twilio still can't connect:

1. **Check Twilio Debugger**: Twilio Console → Monitor → Debugger
2. **Check Jambonz Logs**: `docker compose logs -f sbc-inbound sbc-outbound`
3. **Contact Support**: Provide logs and diagnostic output

## Testing After Fix

Once fixed, test by:

1. **Make a test call** from your Twilio number
2. **Check Twilio Debugger** for successful connection
3. **Check Jambonz logs** for incoming INVITE

