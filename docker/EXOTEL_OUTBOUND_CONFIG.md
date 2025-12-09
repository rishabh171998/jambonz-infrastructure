# Exotel Outbound Call Configuration (Jambonz → Exotel)

## Overview

For **outbound calls**, Jambonz sends INVITEs **TO** Exotel. The configuration is done in **Jambonz**, not in Exotel dashboard.

## Jambonz Carrier Configuration for Outbound

### 1. Outbound SIP Gateway

**Location:** Carriers → Exotel → **Outbound & Registration** tab

**Configuration:**
- **Network address:** `pstn.in4.exotel.com` (or `pstn.in2.exotel.com`)
- **Port:** `5070`
- **Protocol:** `tcp`
- **Outbound:** ✅ Enabled
- **Inbound:** ❌ Disabled (for outbound-only gateway)

**Note:** You can have the same gateway for both inbound and outbound, but it's cleaner to separate them.

### 2. General Settings (Affects Outbound Format)

**Location:** Carriers → Exotel → **General** tab

#### E.164 Syntax
```
✅ Check "Prepend a leading + on origination attempts"
```

This makes Jambonz send:
- ✅ `INVITE sip:+918064061518@pstn.in4.exotel.com:5070`
- ❌ Instead of: `INVITE sip:918064061518@pstn.in4.exotel.com:5070`

**Recommendation:** ✅ Enable this (Exotel supports both, but E.164 is standard)

#### Tech Prefix
```
(Leave empty)
```

Only use if Exotel requires a prefix for routing.

#### Outbound SIP Proxy
```
(Leave empty)
```

Only use if Exotel requires a specific proxy.

### 3. Outbound Settings

**Location:** Carriers → Exotel → **Outbound & Registration** tab

#### From Domain
```
graine1m.pstn.exotel.com
```

This is your Exotel trunk domain. Jambonz will use this in the `From` header:
```
From: <sip:your-username@graine1m.pstn.exotel.com>
```

**Important:** This must match your Exotel trunk configuration.

#### Register Username / Password
```
(Leave empty - IP whitelisting)
```

Since Exotel uses IP whitelisting, registration is not required.

## How Jambonz Formats Outbound INVITEs

When you make an outbound call from Jambonz:

### Request URI Format

**If E.164 is enabled:**
```
INVITE sip:+918064061518@pstn.in4.exotel.com:5070 SIP/2.0
```

**If E.164 is disabled:**
```
INVITE sip:918064061518@pstn.in4.exotel.com:5070 SIP/2.0
```

### From Header Format

```
From: <sip:your-username@graine1m.pstn.exotel.com>;tag=...
```

Where `your-username` is typically:
- Your account username
- Or a configured caller ID
- Or the phone number you're calling from

### To Header Format

```
To: <sip:+918064061518@pstn.in4.exotel.com:5070>
```

Matches the Request URI.

## Exotel Requirements for Outbound

### 1. IP Whitelisting
- Your Jambonz server's public IP must be whitelisted in Exotel dashboard
- This is the same IP used for inbound

### 2. Request URI Format
Exotel accepts:
- ✅ `sip:+918064061518@pstn.in4.exotel.com:5070` (E.164 with +)
- ✅ `sip:918064061518@pstn.in4.exotel.com:5070` (E.164 without +)
- ✅ `sip:08064061518@pstn.in4.exotel.com:5070` (local format)

**Recommendation:** Use E.164 with `+` (standard format)

### 3. From Domain
- Must match your Exotel trunk domain: `graine1m.pstn.exotel.com`
- Configured in Jambonz carrier "Outbound & Registration" → "From Domain"

### 4. Protocol
- **TCP 5070** (recommended for reliability)
- Or **TLS 443** (if you configured TLS)

## Testing Outbound Calls

### 1. Check Gateway Configuration

```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT ipv4, port, protocol, outbound, is_active 
FROM sip_gateways 
WHERE voip_carrier_sid = (
  SELECT voip_carrier_sid FROM voip_carriers WHERE name LIKE '%Exotel%'
) AND outbound = 1;
"
```

**Expected:**
```
ipv4              | port | protocol | outbound | is_active
pstn.in4.exotel.com | 5070 | tcp      | 1        | 1
```

### 2. Check Carrier Settings

```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT name, e164_leading_plus, trunk_type 
FROM voip_carriers 
WHERE name LIKE '%Exotel%';
"
```

**Expected:**
```
e164_leading_plus: 1 (enabled)
trunk_type: static_ip
```

### 3. Monitor Outbound INVITEs

```bash
sudo docker compose logs -f drachtio-sbc | grep -i "invite.*pstn.in"
```

**Expected output:**
```
INVITE sip:+918064061518@pstn.in4.exotel.com:5070 SIP/2.0
From: <sip:username@graine1m.pstn.exotel.com>
```

### 4. Check sbc-outbound Logs

```bash
sudo docker compose logs -f sbc-outbound
```

Look for:
- ✅ INVITE sent to Exotel
- ✅ 100 Trying received
- ✅ 180 Ringing received
- ✅ 200 OK received
- ❌ 403 Forbidden (check From domain)
- ❌ 404 Not Found (check Request URI format)

## Common Outbound Issues

### 1. 403 Forbidden

**Cause:** From domain doesn't match Exotel trunk domain

**Fix:**
- Check "Outbound & Registration" → "From Domain" = `graine1m.pstn.exotel.com`
- Verify in Exotel dashboard that this is your trunk domain

### 2. 404 Not Found

**Cause:** Request URI format is incorrect

**Fix:**
- Enable "E.164 syntax" → "Prepend a leading +"
- Verify phone number format in Request URI

### 3. No Response / Timeout

**Cause:** IP not whitelisted or firewall blocking

**Fix:**
- Verify your Jambonz public IP is whitelisted in Exotel
- Check firewall allows TCP 5070 outbound

### 4. Call Drops Immediately

**Cause:** RTP port range mismatch or codec issues

**Fix:**
- Verify RTP ports 10000-40000 are open (UDP)
- Check codec negotiation (should be PCMA or PCMU)

## Summary

**For Outbound Calls:**
1. ✅ Configure outbound SIP gateway: `pstn.in4.exotel.com:5070` (TCP)
2. ✅ Enable "E.164 syntax" → "Prepend a leading +"
3. ✅ Set "From Domain" = `graine1m.pstn.exotel.com`
4. ✅ Whitelist your Jambonz IP in Exotel dashboard
5. ✅ Test with a simple outbound call

**Jambonz will send:**
```
INVITE sip:+918064061518@pstn.in4.exotel.com:5070 SIP/2.0
From: <sip:username@graine1m.pstn.exotel.com>
```

**Exotel will:**
- Accept the call (if IP is whitelisted)
- Route to the destination phone number
- Send back 200 OK when answered

