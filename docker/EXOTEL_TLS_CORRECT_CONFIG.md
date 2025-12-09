# Exotel TLS Configuration - Correct Setup

Based on Exotel's official TLS integration guide, here's the correct configuration for Jambonz.

## Key Points

1. **Signaling**: TLS on port **443** (NOT 5070)
   - ⚠️ **Common Mistake**: Port 5070 is for TCP, not TLS
   - ✅ **Correct**: TLS uses port 443 (as shown in Exotel's Asterisk config example)
2. **FQDN**: `pstn.in2.exotel.com` (Mumbai DC) or `pstn.in4.exotel.com` (Mumbai Cloud)
3. **Webapp Limitation**: FQDNs cannot be used in the "Allowed IP Addresses" (Inbound) section

## Configuration Steps

### 1. Outbound Gateway (Where Jambonz sends calls TO Exotel)

**In the webapp:**
- Go to: Carriers → Exotel → **Outbound & Registration** tab
- Add/Edit SIP Gateway:
  - **Network address**: `pstn.in2.exotel.com` or `pstn.in4.exotel.com` (Mumbai Cloud)
  - **Port**: `443` ⚠️ **MUST BE 443** (NOT 5070 - that's for TCP, not TLS)
  - **Protocol**: `tls`
  - **Outbound**: ✅ Enabled
  - **Inbound**: ❌ Disabled
  - **Active**: ✅ Enabled

**Or use the script:**
```bash
./fix-exotel-tls-config.sh
```

### 2. Inbound Gateway (Where Exotel sends calls FROM)

**The Problem:**
- The webapp's "Allowed IP Addresses" section (Inbound tab) does NOT allow FQDNs
- You must use actual IP addresses for inbound SIP signaling whitelisting

**The Solution:**

**Option A: Get Exotel's Signaling Server IPs (Recommended)**
1. Contact Exotel support to get the actual IP addresses of:
   - `pstn.in2.exotel.com` (Mumbai DC)
   - `pstn.in4.exotel.com` (Mumbai Cloud)
2. Add these IPs to the "Allowed IP Addresses" section in the webapp

**Option B: Use Media IPs (If Same as Signaling)**
If Exotel uses the same IPs for signaling and media, you can use:
- **Mumbai DC**: `182.76.143.61`, `122.15.8.184`
- **KA DC**: `14.194.10.247`, `61.246.82.75`

**In the webapp:**
- Go to: Carriers → Exotel → **Inbound** tab
- In "Allowed IP Addresses" section:
  - Remove: `pstn.in2.exotel.com:5070` (this is wrong - FQDN not allowed)
  - Add: Exotel's signaling server IP addresses (one per line)
  - Netmask: `32` for each
  - Active: ✅ Enabled

### 3. Media IPs (RTP/SRTP)

The media IPs you have listed are correct:
- `182.76.143.61/32` (Mumbai DC)
- `122.15.8.184/32` (Mumbai DC)
- `14.194.10.247/32` (KA DC)
- `61.246.82.75/32` (KA DC)

These are for RTP media (ports 10000-40000 UDP), not SIP signaling.

## Summary Table

| Direction | Type | Value | Port | Protocol | Where to Configure |
|-----------|------|-------|------|----------|-------------------|
| **Outbound** | Signaling | `pstn.in2.exotel.com` | 443 | TLS | Outbound & Registration tab |
| **Inbound** | Signaling | Exotel's IP addresses | 443 | TLS | Inbound → Allowed IP Addresses |
| **Both** | Media | `182.76.143.61`, etc. | 10000-40000 | UDP (SRTP) | Inbound → Allowed IP Addresses |

## What NOT to Do

❌ **Don't put FQDNs in the Inbound "Allowed IP Addresses" section**
- The webapp will show: "A fully qualified domain name may only be used for outbound calls"
- This is correct - FQDNs are only for outbound gateways

❌ **Don't use port 5070 for TLS**
- Port 5070 is for TCP, not TLS
- TLS uses port 443 (as per Exotel's documentation: "Transport: SIP over TLS (Port 443)")
- The Exotel Asterisk config example shows: `port = 443` and `transport = tls`

❌ **Don't mix signaling and media IPs**
- Signaling IPs: Where SIP INVITEs come from/go to
- Media IPs: Where RTP packets come from/go to
- They might be the same, but they serve different purposes

## Verification

After configuration, verify:

1. **Outbound Gateway**:
   ```sql
   SELECT ipv4, port, protocol, inbound, outbound 
   FROM sip_gateways 
   WHERE voip_carrier_sid = '<your-carrier-sid>' 
     AND outbound = 1;
   ```
   Should show: `pstn.in2.exotel.com`, `443`, `tls`, `0`, `1`

2. **Inbound Gateways**:
   ```sql
   SELECT ipv4, port, protocol, inbound, outbound 
   FROM sip_gateways 
   WHERE voip_carrier_sid = '<your-carrier-sid>' 
     AND inbound = 1;
   ```
   Should show IP addresses (not FQDNs), port `443` or `NULL`, protocol `tls` or `NULL`

## Troubleshooting

**Issue**: "A fully qualified domain name may only be used for outbound calls"
- **Cause**: You're trying to add an FQDN in the Inbound tab
- **Fix**: Remove the FQDN from Inbound, add it to Outbound instead

**Issue**: Calls not connecting
- **Check**: Outbound gateway has `protocol='tls'` and `port=443` (NOT 5070)
- **Check**: Inbound gateways have actual IP addresses (not FQDNs)
- **Check**: Your Jambonz public IP is whitelisted in Exotel dashboard
- **Common Error**: Using port 5070 instead of 443 for TLS - this will cause connection failures

**Issue**: No audio
- **Check**: RTP port range 10000-40000 is open in firewall
- **Check**: Media IPs are correctly configured
- **Check**: SRTP is properly negotiated (check SDP in SIP traces)

