# Exotel Destination URI - Missing Phone Number

## Current Configuration

**Destination URI:**
```
sip:15.207.113.122:5060;transport=tcp
```

**Problem:** Phone number is missing!

## Correct Format

**Destination URI should be:**
```
sip:8064061518@15.207.113.122:5060;transport=tcp
```

**Key difference:** `8064061518@` before the IP address

## Why Twilio Works But Exotel Doesn't

### Twilio (Works Automatically)
- Twilio **automatically** includes the phone number in the Request URI
- You just configure: `sip:your-domain.com`
- Twilio sends: `INVITE sip:+15086908019@your-domain.com`

### Exotel (Requires Manual Configuration)
- Exotel **does NOT** automatically include the phone number
- You must **explicitly** put it in the Destination URI
- If you use: `sip:15.207.113.122:5060;transport=tcp`
- Exotel sends: `INVITE sip:27270013103585148@15.207.113.122` (internal ID)
- If you use: `sip:8064061518@15.207.113.122:5060;transport=tcp`
- Exotel sends: `INVITE sip:8064061518@15.207.113.122` ✅ (phone number)

## Step-by-Step Fix

1. **Go to:** Trunk Details → exotelv1 → Destination URIs
2. **Click on** "Destination URIs" field
3. **Change from:**
   ```
   sip:15.207.113.122:5060;transport=tcp
   ```
4. **To:**
   ```
   sip:8064061518@15.207.113.122:5060;transport=tcp
   ```
5. **Click SAVE**
6. **Wait 1-2 minutes**

## Also Add Whitelisted IP

While you're there, add your Jambonz IP:
- **IP Address:** `15.207.113.122`
- **Subnet Mask:** `32`

## Verification

After updating, make a test call and check:

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
INVITE sip:15.207.113.122 SIP/2.0
```

## Summary

**The phone number MUST be in the Destination URI for Exotel:**
- ✅ `sip:8064061518@15.207.113.122:5060;transport=tcp` (correct)
- ❌ `sip:15.207.113.122:5060;transport=tcp` (missing phone number)

**Twilio vs Exotel:**
- Twilio: Phone number included automatically ✅
- Exotel: Phone number must be in Destination URI manually ⚠️

