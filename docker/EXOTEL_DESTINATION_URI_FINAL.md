# Exotel Destination URI - Final Configuration

## Current Problem

**Current Destination URI:**
```
sip:graineone.sip.graine.ai:5060;transport=tcp
```

**Issue:** Phone number is missing, so Exotel sends internal IDs instead of your phone number.

## Solution

### Option 1: Use FQDN with Phone Number (If Exotel Accepts It)

**Destination URI:**
```
sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp
```

**Note:** This may still cause SIP realm matching issues in Jambonz.

### Option 2: Use IP Address with Phone Number (RECOMMENDED)

**Destination URI:**
```
sip:8064061518@15.207.113.122:5060;transport=tcp
```

**Why this is better:**
- ✅ Phone number included (Exotel will send it in Request URI)
- ✅ Uses IP instead of FQDN (avoids SIP realm matching)
- ✅ Port included (as required by Exotel)

## Step-by-Step Configuration

### For Trunk "exotel"

1. **Go to:** Trunk Details → exotel → Destination URIs
2. **Click on** "Destination URIs" (should be editable)
3. **Change from:**
   ```
   sip:graineone.sip.graine.ai:5060;transport=tcp
   ```
4. **To:**
   ```
   sip:8064061518@15.207.113.122:5060;transport=tcp
   ```
5. **Click SAVE**
6. **Wait 1-2 minutes** for changes to propagate

### For Trunk "exotelv3" (New Trunk)

If you're using the new trunk instead:

1. **Go to:** Trunk Details → exotelv3 → Destination URIs
2. **Click:** "Configure destination URIs"
3. **Add:**
   ```
   sip:8064061518@15.207.113.122:5060;transport=tcp
   ```
4. **Also add whitelisted IP:**
   - IP Address: `15.207.113.122`
   - Subnet Mask: `32`
5. **Click SAVE**

## Alternative Formats (If Above Doesn't Work)

If Exotel doesn't accept the format above, try:

**Format 1 (without +):**
```
sip:8064061518@15.207.113.122:5060;transport=tcp
```

**Format 2 (with +):**
```
sip:+918064061518@15.207.113.122:5060;transport=tcp
```

**Format 3 (E.164 with country code):**
```
sip:918064061518@15.207.113.122:5060;transport=tcp
```

**Format 4 (local format):**
```
sip:08064061518@15.207.113.122:5060;transport=tcp
```

## Verification

After updating, make a test call and check logs:

```bash
sudo docker compose logs -f drachtio-sbc | grep "INVITE sip:"
```

**Expected (CORRECT):**
```
INVITE sip:8064061518@15.207.113.122 SIP/2.0
```

**NOT (WRONG):**
```
INVITE sip:27270013103585148@15.207.113.122 SIP/2.0
INVITE sip:8064061518@graineone.sip.graine.ai:5060;transport=tcp SIP/2.0
```

## Why Port is Required

Exotel's system requires the port to be specified in the Destination URI. This is why you see:
- `:5060;transport=tcp` in the current URI
- The port must be included when adding the phone number

## Summary

**Key Points:**
1. ✅ Phone number MUST be in Destination URI: `8064061518@...`
2. ✅ Port MUST be included: `:5060;transport=tcp`
3. ✅ Use IP address instead of FQDN: `15.207.113.122` (avoids SIP realm matching)
4. ✅ Format: `sip:8064061518@15.207.113.122:5060;transport=tcp`

**After fixing, calls should:**
- ✅ Include phone number in Request URI
- ✅ Be recognized as phone number calls (not user calls)
- ✅ Route to your application correctly

