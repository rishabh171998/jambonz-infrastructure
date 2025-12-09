# Fix Exotel Destination URI - Quick Guide

## Current Configuration (WRONG)

**Destination URIs:**
```
sip:graineone.sip.graine.ai:5060;transport=tcp
```

**Problem:** Phone number is missing, so Exotel sends internal IDs instead.

## Fix: Update Destination URI

**Click on "Destination URIs"** and change it to:

```
sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp
```

**Key change:** Added `+918064061518@` before the FQDN.

## Step-by-Step

1. **Click on "Destination URIs"** section (it should be editable)
2. **Change from:**
   ```
   sip:graineone.sip.graine.ai:5060;transport=tcp
   ```
3. **To:**
   ```
   sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp
   ```
4. **Click "SAVE"** at the bottom
5. **Wait 1-2 minutes** for changes to propagate

## Alternative Formats (If + doesn't work)

If Exotel doesn't accept `+` in the URI, try:

**Option 1 (without +):**
```
sip:918064061518@graineone.sip.graine.ai:5060;transport=tcp
```

**Option 2 (local format):**
```
sip:08064061518@graineone.sip.graine.ai:5060;transport=tcp
```

## Verification

After saving, make a test call and check logs:

```bash
sudo docker compose logs -f drachtio-sbc | grep "INVITE sip:"
```

**Should see:**
```
✅ INVITE sip:+918064061518@15.207.113.122 SIP/2.0
```

**NOT:**
```
❌ INVITE sip:27270013103585148@15.207.113.122 SIP/2.0
```

## Your Current Configuration Summary

✅ **Trunk Name:** exotel  
✅ **Trunk ID:** trmum1b5bb8024884011b3b019c9  
✅ **Phone Number:** +918064061518  
✅ **Whitelisted IP:** 15.207.113.122/32  
❌ **Destination URI:** Missing phone number - **NEEDS FIX**

## After Fixing

Once you update the Destination URI to include the phone number:
1. ✅ Exotel will send: `INVITE sip:+918064061518@15.207.113.122`
2. ✅ Jambonz will find the phone number in database
3. ✅ Call will route to your application
4. ✅ Call will connect successfully

