# How to Enable Inbound on Exotel SIP Gateway

## The Issue

Your SIP gateway `pstn.in2.exotel.com:5070` has **inbound disabled**, which prevents Exotel from sending calls to Jambonz.

## Solution

### Option 1: Enable via Script (Easiest)

```bash
cd /opt/jambonz-infrastructure/docker
sudo ./fix-exotel-gateway-inbound.sh
```

This will automatically enable inbound on the gateway.

### Option 2: Enable via Webapp

1. **Go to Carriers → Edit ExotelMumbai**

2. **Scroll down to find "SIP Gateways" section**
   - It should be below the "Allowed IP Addresses" section
   - Or look for a section showing your gateways

3. **Find the gateway: `pstn.in2.exotel.com:5070`**
   - It should show:
     - Network address: `pstn.in2.exotel.com`
     - Port: `5070`
     - Protocol: `TCP`

4. **Enable the "Inbound" checkbox** for this gateway
   - There should be checkboxes for "Inbound" and "Outbound"
   - Make sure **Inbound** is checked ✅

5. **Click Save**

### Option 3: Enable via SQL (If webapp doesn't work)

```bash
cd /opt/jambonz-infrastructure/docker
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET inbound = 1 
WHERE ipv4 = 'pstn.in2.exotel.com' 
  AND port = 5070 
  AND voip_carrier_sid = (
    SELECT voip_carrier_sid FROM voip_carriers WHERE name = 'ExotelMumbai'
  );
EOF
```

## What You Should See

After enabling inbound, the gateway should show:
- **Network address:** `pstn.in2.exotel.com`
- **Port:** `5070`
- **Protocol:** `TCP`
- **Inbound:** ✅ **Enabled** (this is the key!)
- **Outbound:** ✅ Enabled
- **Active:** ✅ Enabled

## Verification

After enabling, verify it worked:

```bash
cd /opt/jambonz-infrastructure/docker
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  ipv4,
  port,
  protocol,
  inbound,
  outbound,
  is_active
FROM sip_gateways 
WHERE ipv4 = 'pstn.in2.exotel.com';
"
```

You should see `inbound = 1`.

## Why This Matters

- **Inbound = 0:** Jambonz will **reject** incoming INVITEs from Exotel → "busy" status
- **Inbound = 1:** Jambonz will **accept** incoming INVITEs from Exotel → calls work

The "Allowed IP Addresses" you configured are for **media (RTP)**, but the SIP gateway inbound setting is for **signaling (SIP INVITE)**.

## Current Configuration Status

✅ **Correct:**
- Phone number `08064061518` configured
- Application associated
- Allowed IP addresses (Exotel media IPs)
- SIP gateway address: `pstn.in2.exotel.com`
- Protocol: `TCP`

❌ **Needs Fix:**
- SIP gateway inbound: **Must be enabled**

After enabling inbound, test an inbound call from Exotel. It should work!

