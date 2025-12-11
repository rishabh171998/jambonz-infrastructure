# SIP Registration 403 Forbidden - Fix Guide

## Problem

SIP REGISTER requests are being rejected with `403 Forbidden`:
```
REGISTER sip:15.207.113.122 SIP/2.0
From: "5001" <sip:5001@15.207.113.122>
...
SIP/2.0 403 Forbidden
```

## Root Causes

1. **No client credentials** in database
2. **No registration webhook** configured
3. **Client is inactive** (`is_active = 0`)
4. **SIP realm mismatch**
5. **Registration webhook returning failure**

## Quick Fix

### Option 1: Create SIP Client (Recommended)

Run the fix script:
```bash
sudo ./fix-sip-registration-403.sh
```

This will:
- Extract username/domain from logs
- Find or create account
- Create SIP client with credentials
- Activate client
- Restart registrar

### Option 2: Manual Fix

**Step 1: Get Account SID**
```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT account_sid, name, sip_realm 
FROM accounts 
WHERE sip_realm IS NOT NULL;
"
```

**Step 2: Create SIP Client**
```bash
# Replace ACCOUNT_SID, USERNAME, and PASSWORD
ACCOUNT_SID="your-account-sid"
USERNAME="5001"
PASSWORD="your-password"

CLIENT_SID=$(uuidgen | tr '[:upper:]' '[:lower:]')

sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones <<EOF
INSERT INTO clients (
  client_sid,
  account_sid,
  username,
  password,
  is_active,
  allow_direct_app_calling,
  allow_direct_queue_calling,
  allow_direct_user_calling
) VALUES (
  '$CLIENT_SID',
  '$ACCOUNT_SID',
  '$USERNAME',
  '$PASSWORD',
  1,
  1,
  1,
  1
);
EOF
```

**Step 3: Restart Registrar**
```bash
sudo docker compose restart registrar
```

## From Logs

Your logs show:
- **Username**: `5001`
- **Domain**: `15.207.113.122` (IP address)
- **Source IP**: `199.127.62.109:6444`

## Diagnostic

Run comprehensive diagnostic:
```bash
sudo ./diagnose-sip-registration-403.sh
```

This checks:
- Recent REGISTER attempts
- Account SIP realm matching
- Client credentials
- Registration webhook
- Registrar logs

## Common Issues

### Issue 1: Domain is IP Address

If domain is `15.207.113.122` (IP), you need to:
1. Set SIP realm to FQDN (e.g., `graineone.sip.graine.ai`)
2. Or ensure account has SIP realm matching the IP

**Fix:**
```bash
# Update account SIP realm
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET sip_realm = '15.207.113.122'
WHERE account_sid = 'your-account-sid';
"
```

### Issue 2: No Client Credentials

Registration requires either:
- Client credentials in `clients` table, OR
- Registration webhook that authenticates

**Create client:**
```bash
sudo ./fix-sip-registration-403.sh
```

### Issue 3: Registration Webhook Failing

If using webhook authentication, check webhook returns:
```json
{
  "status": "ok",
  "message": "authentication granted"
}
```

**Check webhook logs** to see what it's returning.

## Verification

After creating client:

1. **Check client exists:**
   ```bash
   sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
   SELECT client_sid, username, is_active 
   FROM clients 
   WHERE username = '5001';
   "
   ```

2. **Try registering again** from your SIP client

3. **Check registrar logs:**
   ```bash
   sudo docker compose logs -f registrar | grep -i "5001"
   ```

4. **Check for successful registration:**
   ```bash
   sudo docker compose logs drachtio-sbc | grep -i "200 OK" | tail -5
   ```

## Expected Behavior

After fix, you should see:
```
REGISTER sip:15.207.113.122 SIP/2.0
...
SIP/2.0 200 OK
```

Instead of:
```
SIP/2.0 403 Forbidden
```

## Summary

**Quick fix:**
```bash
sudo ./fix-sip-registration-403.sh
```

This will create the SIP client `5001` with credentials and enable registration.

