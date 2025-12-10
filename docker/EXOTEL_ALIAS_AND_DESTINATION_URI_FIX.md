# Exotel Alias and Destination URI Fix

## Problem Identified

**Current Configuration:**
- **Alias:** `91806406151` ❌ (missing last digit `8`)
- **Phone Number:** `+918064061518` ✅
- **Destination URI:** `sip:graineone.sip.graine.ai:5060;transport=tcp` ❌ (missing phone number, using FQDN)

**Result:**
- Exotel sends: `INVITE sip:91806406151@graineone.sip.graine.ai:5060;transport=tcp` ❌
- Missing last digit `8`
- Using FQDN (causes SIP realm matching)

## Fix Both Issues

### Fix 1: Update Alias

**In Exotel Dashboard:**
1. Go to: Trunk Details → Exotelv1 → Basic Information
2. Find **"Alias"** field
3. Change from: `91806406151`
4. To: `8064061518` (or `918064061518` - match your phone number format)
5. Click SAVE

**Note:** The Alias is what Exotel uses in the Request URI user part.

### Fix 2: Update Destination URI

**In Exotel Dashboard:**
1. Go to: Trunk Details → Exotelv1 → Destination URIs
2. Click on "Destination URIs" field
3. Change from:
   ```
   sip:graineone.sip.graine.ai:5060;transport=tcp
   ```
4. To:
   ```
   sip:8064061518@15.207.113.122:5060;transport=tcp
   ```
5. Click SAVE

**Why use IP instead of FQDN:**
- `graineone.sip.graine.ai` → Matches SIP realm → Treated as user call
- `15.207.113.122` → No SIP realm match → Treated as phone number call

### Fix 3: Add Whitelisted IP

**In Exotel Dashboard:**
1. Go to: Trunk Details → Exotelv1 → Whitelisted IPs
2. Click "Add IP addresses"
3. **IP Address:** `15.207.113.122`
4. **Subnet Mask:** `32`
5. Click SAVE

## Correct Configuration Summary

**Basic Information:**
- **Alias:** `8064061518` (or `918064061518` - must match phone number format)
- **Phone Number:** `+918064061518`

**Destination URIs:**
- `sip:8064061518@15.207.113.122:5060;transport=tcp`

**Whitelisted IPs:**
- `15.207.113.122/32`

## After Fixing

**Expected Request URI:**
```
INVITE sip:8064061518@15.207.113.122 SIP/2.0
```

**NOT:**
```
INVITE sip:91806406151@graineone.sip.graine.ai:5060;transport=tcp SIP/2.0
```

## Verification

After updating both Alias and Destination URI:

1. Wait 1-2 minutes for changes to propagate
2. Make a test call
3. Check logs:
   ```bash
   sudo docker compose logs -f drachtio-sbc | grep "INVITE sip:"
   ```

**Should see:**
- ✅ `INVITE sip:8064061518@15.207.113.122` (correct format)
- ✅ Phone number complete (not missing digits)
- ✅ Using IP (not FQDN)

## Why Alias Matters

Exotel uses the **Alias** field value in the Request URI user part. If Alias is wrong, the phone number in the Request URI will be wrong, and Jambonz won't be able to route the call.

**Make sure Alias matches the phone number format you have in Jambonz database:**
- If database has: `8064061518` → Use Alias: `8064061518`
- If database has: `918064061518` → Use Alias: `918064061518`
- If database has: `08064061518` → Use Alias: `08064061518`

