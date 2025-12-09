# Exotel vSIP Inbound Call Troubleshooting Guide

## Common Issues and Solutions

### Issue 1: No INVITE Received from Exotel

**Symptoms:**
- Calls from Exotel don't reach Jambonz
- No SIP INVITE in SBC logs

**Possible Causes:**
1. **IP not whitelisted in Exotel**
   - **Solution:** Add your Jambonz public IP to Exotel dashboard
   - Location: Exotel Dashboard → Trunk Settings → Whitelisted IPs
   - Add: `13.203.223.245` (your Jambonz IP)

2. **Wrong SIP Gateway Configuration**
   - **Current (Wrong):** `graine1m.pstn.exotel.com`
   - **Should be:** `pstn.in2.exotel.com`
   - **Port:** `5070`
   - **Protocol:** `TCP`

3. **Firewall/Security Group Blocking**
   - **Solution:** Open TCP 5070 in AWS Security Group
   - Allow from: Exotel IPs (182.76.143.61, 122.15.8.184, etc.)

### Issue 2: INVITE Received but Call Fails

**Symptoms:**
- INVITE appears in logs
- Call doesn't connect
- 403/404/487 errors

**Possible Causes:**
1. **Inbound IPs Not Whitelisted in Jambonz**
   - **Solution:** Add Exotel IPs to carrier's inbound whitelist:
     - 182.76.143.61 / 32
     - 122.15.8.184 / 32
     - 14.194.10.247 / 32
     - 61.246.82.75 / 32

2. **No Application Associated**
   - **Solution:** Ensure carrier has `application_sid` set
   - Or configure call routing in Jambonz

3. **SBC Not Listening on Correct Interface**
   - **Check:** SBC should listen on `0.0.0.0:5060` (all interfaces)
   - **Verify:** `docker-compose.yaml` SBC configuration

### Issue 3: No Audio (One-Way or No Audio)

**Symptoms:**
- Call connects but no audio
- One-way audio

**Possible Causes:**
1. **RTP Port Range Mismatch**
   - **Exotel requires:** UDP 10000-40000
   - **Check:** Your `docker-compose.yaml` rtpengine ports
   - **Solution:** Update to overlap with Exotel's range

2. **NAT Traversal Issues**
   - **Solution:** Ensure `HOST_IP` is set correctly in `.env`
   - Verify rtpengine uses correct public IP

3. **Firewall Blocking RTP**
   - **Solution:** Open UDP 10000-40000 in AWS Security Group
   - Allow from: Exotel media IPs

### Issue 4: Codec Negotiation Failure

**Symptoms:**
- Call connects but immediately drops
- SDP negotiation errors in logs

**Possible Causes:**
1. **Codec Mismatch**
   - **Exotel supports:** PCMA (preferred), PCMU
   - **Solution:** Ensure Jambonz is configured to accept these codecs

2. **SRTP Issues (if using TLS)**
   - **Solution:** If using TLS, ensure SRTP is properly configured
   - For TCP, use regular RTP (not SRTP)

## Diagnostic Steps

### Step 1: Run Diagnostic Script
```bash
cd /opt/jambonz-infrastructure/docker
sudo ./diagnose-exotel-inbound.sh
```

### Step 2: Check SBC Logs
```bash
sudo docker compose logs sbc-inbound --tail 100 | grep -i invite
```

### Step 3: Verify Carrier Configuration
```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  vc.name,
  vc.is_active,
  vc.application_sid,
  sg.ipv4,
  sg.port,
  sg.protocol,
  sg.inbound,
  sg.is_active
FROM voip_carriers vc
LEFT JOIN sip_gateways sg ON vc.voip_carrier_sid = sg.voip_carrier_sid
WHERE vc.name LIKE '%Exotel%';
"
```

### Step 4: Test SIP Connectivity
```bash
# Test if Exotel can reach your SBC
# From your server, check if SBC is listening:
sudo netstat -tuln | grep 5060

# Test DNS resolution:
nslookup pstn.in2.exotel.com
```

### Step 5: Check Feature Server Logs
```bash
sudo docker compose logs feature-server --tail 200 | grep -iE "exotel|carrier|inbound|error"
```

## Correct Configuration Checklist

### Carrier Settings
- [ ] Carrier name: `ExotelMumbai` or similar
- [ ] Active: ✅ Checked
- [ ] E.164 syntax: ✅ Prepend leading +
- [ ] Require SIP Register: ❌ Unchecked

### SIP Gateway
- [ ] Network address: `pstn.in2.exotel.com` (NOT `graine1m.pstn.exotel.com`)
- [ ] Port: `5070`
- [ ] Protocol: `TCP` (NOT UDP)
- [ ] Inbound: ✅ Checked
- [ ] Outbound: ✅ Checked
- [ ] Active: ✅ Checked
- [ ] Pad crypto: ✅ Checked (optional)

### Inbound IP Whitelist
- [ ] 182.76.143.61 / 32
- [ ] 122.15.8.184 / 32
- [ ] 14.194.10.247 / 32
- [ ] 61.246.82.75 / 32

### Network/Firewall
- [ ] Jambonz IP whitelisted in Exotel dashboard
- [ ] TCP 5070 open in AWS Security Group
- [ ] UDP 10000-40000 open in AWS Security Group
- [ ] HOST_IP set correctly in `.env`

### RTP Configuration
- [ ] RTP port range overlaps with 10000-40000
- [ ] rtpengine configured with correct public IP

## Quick Fixes

### Fix 1: Update SIP Gateway
```sql
UPDATE sip_gateways 
SET ipv4 = 'pstn.in2.exotel.com',
    port = 5070,
    protocol = 'tcp'
WHERE voip_carrier_sid = '<your-carrier-sid>';
```

### Fix 2: Add Missing Inbound IPs
Go to Jambonz webapp → Carriers → Edit → Inbound tab → Add IPs

### Fix 3: Verify IP Whitelisting
1. Get your Jambonz public IP from `.env` file
2. Go to Exotel dashboard
3. Navigate to Trunk Settings
4. Add your IP to Whitelisted IPs

## Still Not Working?

1. **Check Exotel Dashboard:**
   - Verify trunk is active
   - Check call logs for errors
   - Verify IP whitelisting

2. **Enable Debug Logging:**
   - Set `JAMBONES_LOGLEVEL=debug` in `docker-compose.yaml`
   - Restart services: `sudo ./restart-all.sh`
   - Review detailed logs

3. **Contact Exotel Support:**
   - Provide trunk ID: `trmum1c8b50c05af3fbe62c519c9`
   - Provide your Jambonz IP
   - Provide SIP trace logs

