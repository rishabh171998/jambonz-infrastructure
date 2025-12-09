# How to Enable Inbound for Exotel Gateway in Jambonz Webapp

## Understanding the Webapp Structure

The Jambonz webapp **separates SIP gateways into two tabs**:
- **Inbound tab**: Gateways with `inbound: 1` (for receiving calls FROM carriers)
- **Outbound tab**: Gateways with `outbound: 1` (for sending calls TO carriers)

A gateway can be **both inbound and outbound** (`inbound: 1, outbound: 1`), which is what you need for Exotel.

## The Problem

Your gateway `pstn.in2.exotel.com:5070` is currently **only in the Outbound tab**, which means:
- `inbound: 0` ❌
- `outbound: 1` ✅

This means Jambonz can send calls TO Exotel, but Exotel **cannot send calls TO Jambonz**.

## Solution Options

### Option 1: Enable via SQL Script (Easiest)

```bash
cd /opt/jambonz-infrastructure/docker
sudo ./fix-exotel-gateway-inbound.sh
```

This will set `inbound: 1` on the existing gateway, making it appear in both tabs.

### Option 2: Add Gateway in Inbound Tab (Webapp)

1. Go to **Carriers** → **Edit ExotelMumbai**
2. Click the **"Inbound"** tab
3. Click the **"+"** button to add a new gateway
4. Enter:
   - **Network address:** `pstn.in2.exotel.com`
   - **Netmask:** `32`
   - **Active:** ✅ Checked
   - **Pad crypto:** ✅ Checked (optional)
5. Click **Save**

**Note:** This will create a **separate gateway entry** in the database. The webapp will show it in the Inbound tab, and your existing one will remain in the Outbound tab. Both will work, but it's cleaner to use Option 1.

### Option 3: Update via SQL Directly

```bash
cd /opt/jambonz-infrastructure/docker
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
UPDATE sip_gateways 
SET inbound = 1 
WHERE voip_carrier_sid = (
  SELECT voip_carrier_sid FROM voip_carriers WHERE name = 'ExotelMumbai'
)
AND ipv4 = 'pstn.in2.exotel.com' 
AND port = 5070;
EOF
```

## After the Fix

After enabling inbound, the gateway will have:
- `inbound: 1` ✅ (appears in Inbound tab)
- `outbound: 1` ✅ (appears in Outbound tab)

In the webapp, you'll see:
- **Inbound tab:** Shows `pstn.in2.exotel.com:5070`
- **Outbound tab:** Shows `pstn.in2.exotel.com:5070`

This is **correct** - the same gateway needs to be in both tabs for bidirectional communication with Exotel.

## Verification

After the fix, verify it worked:

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
WHERE ipv4 = 'pstn.in2.exotel.com' AND port = 5070;
"
```

You should see:
- `inbound = 1` ✅
- `outbound = 1` ✅

## Why This Matters

- **Inbound = 0:** Jambonz **rejects** incoming INVITEs from Exotel → "busy" status
- **Inbound = 1:** Jambonz **accepts** incoming INVITEs from Exotel → calls work

The "Allowed IP Addresses" in the Inbound tab are for **RTP media**, but the SIP gateway inbound setting is for **SIP signaling**.

