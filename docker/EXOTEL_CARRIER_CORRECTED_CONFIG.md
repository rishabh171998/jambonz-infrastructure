# Exotel vSIP - Corrected Carrier Configuration

## Issues Found in Your Current Configuration

### ❌ Issue 1: Wrong Network Address
- **Current:** `graine1m.pstn.exotel.com`
- **Should be:** `pstn.in2.exotel.com` (Mumbai DC primary)
- **Why:** `graine1m.pstn.exotel.com` is your account domain, not Exotel's signaling server

### ❌ Issue 2: Wrong Protocol
- **Current:** `UDP`
- **Should be:** `TCP`
- **Why:** Exotel vSIP uses TCP (port 5070) or TLS (port 443) for SIP signaling, not UDP

## Corrected Configuration

### SIP Gateway (Primary)
```
Network address: pstn.in2.exotel.com
Port: 5070
Protocol: TCP  ← Change from UDP to TCP
Netmask: 32
Inbound: ✅ Checked
Outbound: ✅ Checked
Active: ✅ Checked
Pad crypto: ✅ Checked (optional but recommended)
Send OPTIONS ping: (optional)
```

### Optional: Add Backup Gateway
For redundancy, you can also add:
```
Network address: pstn.in4.exotel.com
Port: 5070
Protocol: TCP
Netmask: 32
Inbound: ✅ Checked
Outbound: ✅ Checked
Active: ✅ Checked
```

### Inbound - Allowed IP Addresses
✅ **These are correct:**
- 182.76.143.61 / 32
- 122.15.8.184 / 32
- 14.194.10.247 / 32
- 61.246.82.75 / 32

### General Settings
✅ **These are correct:**
- E.164 syntax: ✅ Prepend a leading +
- Require SIP Register: ❌ Unchecked (correct - Exotel uses IP whitelisting)

### Outbound & Registration Tab
**From Domain:** (should be set to)
```
graine1m.pstn.exotel.com
```
This is where you use your account domain - in the "From Domain" field for outbound calls.

## Summary of Changes Needed

1. **Change SIP Gateway Network Address:**
   - From: `graine1m.pstn.exotel.com`
   - To: `pstn.in2.exotel.com`

2. **Change SIP Gateway Protocol:**
   - From: `UDP`
   - To: `TCP`

3. **Keep everything else as is** (inbound IPs are correct)

## Why These Changes Matter

- **Wrong network address:** Exotel won't be able to route SIP signaling to your server
- **Wrong protocol:** UDP won't work - Exotel vSIP requires TCP or TLS for signaling
- **Correct inbound IPs:** These allow Exotel's media servers to send RTP to your Jambonz server

