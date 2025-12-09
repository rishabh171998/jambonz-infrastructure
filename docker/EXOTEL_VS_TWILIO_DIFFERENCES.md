# Exotel vs Twilio - Key Differences

## Signaling Protocol Differences

| Provider | Protocol | Port | Notes |
|----------|----------|------|-------|
| **Twilio** | UDP | 5060 | Standard SIP UDP |
| **Exotel** | TCP | 5070 | More reliable, connection-oriented |

## Your Current Configuration

### ✅ Outbound (Correct)
- **FQDN**: `pstn.in4.exotel.com`
- **Port**: `5070`
- **Protocol**: `tcp`
- **Status**: ✅ Correct!

### ❌ Inbound (Needs Fix)
- **Current**: IPs with `udp` port `5060`
- **Should be**: Exotel signaling IPs with `tcp` port `5070`

## The Problem

You have these IPs configured as inbound gateways:
- `61.246.82.75:5060` (udp)
- `122.15.8.184:5060` (udp)
- `14.194.10.247:5060` (udp)
- `182.76.143.61:5060` (udp)

**These are MEDIA IPs** (for RTP), not signaling IPs!

According to Exotel docs:
- **Signaling**: TCP port 5070 (from `pstn.in2.exotel.com` or `pstn.in4.exotel.com`)
- **Media**: UDP ports 10000-40000 (from the IPs you have listed)

## The Fix

For inbound SIP signaling, you need:

1. **Get Exotel's signaling server IPs** (contact Exotel support)
   - IP addresses of `pstn.in2.exotel.com` (Mumbai DC)
   - IP addresses of `pstn.in4.exotel.com` (Mumbai Cloud)

2. **Configure in webapp**:
   - Go to **Carriers → Exotel → Inbound** tab
   - Remove the UDP 5060 entries
   - Add Exotel's signaling server IPs with:
     - Port: `5070`
     - Protocol: `tcp`
     - Inbound: ✅ Enabled

## Why This Matters

- **Signaling** (SIP): Controls call setup, teardown, DTMF
- **Media** (RTP): Carries actual audio

They use different IPs and ports:
- SIP signaling: TCP 5070
- RTP media: UDP 10000-40000

## Quick Fix Script

If Exotel uses the same IPs for signaling and media, you can update them:

```bash
./docker/fix-exotel-inbound-tcp.sh
```

This will change inbound gateways from UDP 5060 to TCP 5070.

## Verification

After fixing, your configuration should show:

**Outbound:**
- `pstn.in4.exotel.com:5070` (tcp) ✅

**Inbound:**
- Exotel signaling IPs: `5070` (tcp) ✅
- (Media IPs are handled separately by RTP engine)

## Summary

✅ **Outbound**: Already correct (TCP 5070)
❌ **Inbound**: Need to change from UDP 5060 to TCP 5070
📋 **Action**: Contact Exotel for signaling server IPs, or update existing IPs to TCP 5070

