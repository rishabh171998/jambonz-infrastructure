# Exotel vSIP to Jambonz Carrier Configuration

## Exotel Trunk Details
- **Trunk Name:** Test
- **Trunk ID:** trmum1c8b50c05af3fbe62c519c9
- **Domain:** graine1m.pstn.exotel.com
- **Phone Number:** +918064061518
- **Destination URI:** sip:graineone.sip.graine.ai:5060;transport=tcp
- **Auth Type:** IP-WHITELIST

## Exotel vSIP Configuration Details

### Signaling Servers (Mumbai PoP)
- **TCP:** pstn.in2.exotel.com:5070
- **TLS:** pstn.in2.exotel.com:443
- **Alternative (Cloud):** pstn.in4.exotel.com

### Media Servers (Mumbai DC)
- **IPs:** 182.76.143.61, 122.15.8.184
- **Port Range:** UDP 10000-40000

### Media Servers (KA DC)
- **IPs:** 14.194.10.247, 61.246.82.75
- **Port Range:** UDP 10000-40000

### Codecs
- **Preferred:** PCMA (G.711 A-law)
- **Supported:** PCMU (G.711 μ-law)

## Jambonz Carrier Configuration

### Step 1: Basic Information

**Carrier name:**
```
Exotel vSIP - Test
```

**Select a predefined carrier:**
```
None
```

**Active:**
```
✅ Checked
```

### Step 2: General Settings

**E.164 syntax:**
```
✅ Check "Prepend a leading + on origination attempts"
```

**Authentication:**
```
❌ Do NOT check "Require SIP Register" (Exotel uses IP whitelisting)
```

**Tech prefix:**
```
(Leave empty)
```

**SIP Diversion Header:**
```
(Leave empty)
```

**Outbound SIP Proxy:**
```
(Leave empty)
```

### Step 3: SIP Gateways

You need to add **multiple SIP gateways** for redundancy:

#### Gateway 1 (Mumbai DC - Primary)
- **Network address:** `pstn.in2.exotel.com`
- **Port:** `5070` (for TCP) or `443` (for TLS)
- **Netmask:** `32`
- **Inbound:** ✅ Checked
- **Outbound:** ✅ Checked
- **Protocol:** Select `tcp` (or `tls` if using TLS)

#### Gateway 2 (Mumbai Cloud - Backup)
- **Network address:** `pstn.in4.exotel.com`
- **Port:** `5070` (for TCP) or `443` (for TLS)
- **Netmask:** `32`
- **Inbound:** ✅ Checked
- **Outbound:** ✅ Checked
- **Protocol:** Select `tcp` (or `tls` if using TLS)

#### Gateway 3 (Media Server - Mumbai DC)
- **Network address:** `182.76.143.61`
- **Port:** `5060`
- **Netmask:** `32`
- **Inbound:** ✅ Checked
- **Outbound:** ❌ Unchecked (media only)
- **Protocol:** `udp`

#### Gateway 4 (Media Server - Mumbai DC Backup)
- **Network address:** `122.15.8.184`
- **Port:** `5060`
- **Netmask:** `32`
- **Inbound:** ✅ Checked
- **Outbound:** ❌ Unchecked (media only)
- **Protocol:** `udp`

### Step 4: Inbound Settings

**Allowed IP Addresses (Static IP Whitelist):**

Add Exotel's signaling and media IPs:

1. **182.76.143.61** / **32** (Mumbai DC signaling/media)
2. **122.15.8.184** / **32** (Mumbai DC signaling/media)
3. **14.194.10.247** / **32** (KA DC signaling/media)
4. **61.246.82.75** / **32** (KA DC signaling/media)

**Note:** You may also need to whitelist the FQDN IPs. Check current IPs for:
- `pstn.in2.exotel.com`
- `pstn.in4.exotel.com`

### Step 5: Outbound Settings

**From Domain:**
```
graine1m.pstn.exotel.com
```

**Register Username:** (Leave empty - IP whitelisting)

**Register Password:** (Leave empty - IP whitelisting)

## Important Notes

### 1. RTP Port Range
Ensure your Jambonz RTP port range (configured in `docker-compose.yaml`) overlaps with Exotel's range:
- **Exotel:** 10000-40000
- **Jambonz:** Should be within this range (e.g., 10000-20000 or 40000-60000)

### 2. IP Whitelisting
You need to provide **your Jambonz server's public IP** to Exotel for whitelisting. This is typically your EC2 instance's Elastic IP.

### 3. Codec Configuration
Jambonz should be configured to prefer PCMA (G.711 A-law) codec.

### 4. NAT Traversal
Ensure Jambonz is configured with:
- `nat=force_rport`
- `externip=<your-public-ip>`

### 5. Testing
After configuration:
1. Test inbound call from Exotel → Jambonz
2. Test outbound call from Jambonz → Exotel
3. Verify audio in both directions
4. Check SIP logs for any errors

## Troubleshooting

### No INVITE Received
- Verify your IP is whitelisted in Exotel dashboard
- Check firewall rules allow TCP 5070/443 and UDP 10000-40000

### 403 Forbidden
- Verify From domain matches: `graine1m.pstn.exotel.com`
- Check SIP gateway configuration

### No Audio
- Verify RTP port range is open (UDP 10000-40000)
- Check codec negotiation (should be PCMA or PCMU)
- Verify NAT traversal settings

### Call Drops
- Check RTP timeout settings
- Verify symmetric RTP configuration
- Check for NAT issues

