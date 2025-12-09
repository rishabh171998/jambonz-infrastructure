# Exotel Inbound Call Fix - Quick Reference

## Problem

Exotel is sending INVITEs with **internal IDs** instead of your phone number:

❌ **Current (Wrong):**
```
INVITE sip:27270013103585148@15.207.113.122
INVITE sip:1272500017707497486@15.207.113.122
```

✅ **Should be:**
```
INVITE sip:+918064061518@15.207.113.122
INVITE sip:08064061518@15.207.113.122
```

**Result:** Jambonz returns `404 Not Found` because it can't find the phone number.

## Root Cause

The **Destination URI** in Exotel dashboard doesn't include your phone number.

## Fix in Exotel Dashboard

### Step 1: Go to Exotel Dashboard
- Navigate to: **Trunk Configuration** or **vSIP Settings**
- Find your trunk: `trmum1c8b50c05af3fbe62c519c9`

### Step 2: Update Destination URI

**Current (WRONG):**
```
sip:graineone.sip.graine.ai:5060;transport=tcp
```

**Change to (CORRECT - Option 1 - Recommended):**
```
sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp
```

**OR (Option 2 - If Exotel doesn't accept +):**
```
sip:918064061518@graineone.sip.graine.ai:5060;transport=tcp
```

**OR (Option 3 - Without country code):**
```
sip:08064061518@graineone.sip.graine.ai:5060;transport=tcp
```

### Step 3: Save and Wait
1. Click **Save** or **Update**
2. Wait **1-2 minutes** for changes to propagate
3. Make a test call

## Verification

After fixing, monitor the logs:

```bash
sudo docker compose logs -f drachtio-sbc | grep "INVITE sip:"
```

**You should see:**
```
INVITE sip:+918064061518@15.207.113.122 SIP/2.0
```

**Instead of:**
```
INVITE sip:27270013103585148@15.207.113.122 SIP/2.0
```

## Jambonz Configuration Status

✅ **Phone Numbers Configured:**
- `918064061518` → Application: `08d78564-d3f6-4db4-95ce-513ae757c2c9`
- `08064061518` → Application: `08d78564-d3f6-4db4-95ce-513ae757c2c9`

✅ **Jambonz is ready** - it just needs Exotel to send the correct phone number in the Request URI.

## Why This Happens

Exotel uses internal IDs for routing within their network. When sending to your SIP server, it needs to know:
1. **Where to send** (your FQDN/IP) ✅ Already configured
2. **What phone number** to put in the Request URI ❌ Missing

By including the phone number in the Destination URI, you're telling Exotel:
> "When routing calls to this trunk, put the phone number in the Request URI"

## After Fixing

Once Exotel sends the correct Request URI:
1. ✅ Jambonz will find the phone number in the database
2. ✅ Jambonz will route to the assigned application
3. ✅ Call will connect successfully

## Troubleshooting

### Still getting 404 after fix?

1. **Check Exotel dashboard** - Verify destination URI was saved
2. **Wait 2-3 minutes** - Changes may take time to propagate
3. **Check logs** - Verify new INVITEs have phone number:
   ```bash
   sudo docker compose logs --since 5m drachtio-sbc | grep "INVITE sip:" | tail -5
   ```

### Still seeing internal IDs?

- Exotel may be caching the old configuration
- Try making a call from a different number
- Contact Exotel support if issue persists

