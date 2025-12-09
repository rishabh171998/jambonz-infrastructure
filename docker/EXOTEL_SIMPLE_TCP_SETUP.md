# Exotel Simple TCP Setup (Like Twilio)

Based on Exotel's official TCP documentation, here's the simple setup.

## Quick Summary

**TCP Setup (Simple - Recommended):**
- **FQDN**: `pstn.in2.exotel.com` or `pstn.in4.exotel.com` (Mumbai Cloud)
- **Port**: `5070`
- **Protocol**: `tcp` (NOT TLS)
- **Media**: UDP 10000-40000

**TLS Setup (If you need encryption):**
- **FQDN**: `pstn.in2.exotel.com` or `pstn.in4.exotel.com`
- **Port**: `443` (NOT 5070)
- **Protocol**: `tls`
- **Media**: UDP 10000-40000 (SRTP)

## Your Current Issue

You have:
- ✅ FQDN: `pstn.in4.exotel.com` (correct)
- ✅ Port: `5070` (correct for TCP)
- ❌ Protocol: `TLS` (WRONG - should be `tcp`)

**Fix:** Change protocol from `TLS` to `tcp` in the webapp.

## Simple Setup Steps

### Option 1: Use the Script (Easiest)

```bash
./docker/fix-exotel-simple.sh
```

This will set:
- FQDN: `pstn.in4.exotel.com`
- Port: `5070`
- Protocol: `tcp`

### Option 2: Manual Webapp Configuration

1. Go to **Carriers → Exotel → Outbound & Registration**
2. Edit the SIP Gateway:
   - **Network address**: `pstn.in4.exotel.com`
   - **Port**: `5070`
   - **Protocol**: `tcp` ⚠️ **Change from TLS to TCP**
   - **Outbound**: ✅ Enabled
   - **Inbound**: ❌ Disabled
   - **Active**: ✅ Enabled

## Port & Protocol Reference

| Protocol | Port | Use Case |
|----------|------|----------|
| **TCP** | 5070 | Simple setup (like Twilio) - **Recommended** |
| **TLS** | 443 | Encrypted setup (more complex) |
| **UDP** | 5060 | Not recommended for SIP trunks |

## Exotel Documentation Confirms

From Exotel's TCP guide:
- **Transport**: SIP over TCP (Port 5070)
- **FQDN**: `pstn.in2.exotel.com` or `pstn.in4.exotel.com`
- **Sample config**: `host = pstn.in2.exotel.com`, `port = 5070`, `transport = tcp`

## Verification

After configuration, verify in database:

```sql
SELECT ipv4, port, protocol, inbound, outbound 
FROM sip_gateways 
WHERE voip_carrier_sid = '<your-carrier-sid>';
```

Should show:
- `ipv4`: `pstn.in4.exotel.com`
- `port`: `5070`
- `protocol`: `tcp` (NOT `tls`)
- `outbound`: `1`
- `inbound`: `0`

## Common Mistakes

❌ **Port 5070 with protocol TLS**
- Port 5070 is for TCP, not TLS
- TLS uses port 443

❌ **Port 443 with protocol TCP**
- Port 443 is for TLS, not TCP
- TCP uses port 5070

✅ **Correct**: Port 5070 + Protocol TCP (Simple, like Twilio)

## Next Steps

1. Run the script or manually change protocol to `tcp`
2. Test outbound calls
3. For inbound, configure phone numbers in Exotel dashboard
4. Whitelist your Jambonz public IP in Exotel

That's it! Simple and straightforward, just like Twilio.

