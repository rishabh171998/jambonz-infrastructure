# Fix Recording Issue - Complete Guide

## Issues Identified

1. **Recording Disabled**: `record_all_calls = 0` in database
2. **Known Bug**: Recording interferes with audio (bug in `jambonz/feature-server`)
3. **Missing Configuration**: WebSocket or bucket credentials may be missing

## Quick Fix

### Step 1: Enable Recording

Run the fix script on your server:

```bash
cd /opt/jambonz-infrastructure/docker
sudo ./fix-recording-complete.sh
```

Or manually:

```bash
# Get your account SID
ACCOUNT_SID=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT account_sid 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
")

# Enable recording
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET record_all_calls = 1 
WHERE account_sid = '$ACCOUNT_SID';
"

# Restart feature-server
sudo docker compose restart feature-server
```

### Step 2: Verify Bucket Credentials

Recording requires S3 bucket credentials configured in the account:

1. Go to webapp: `https://sipwebapp.graine.ai` (or `http://sip.graine.ai:3001`)
2. Navigate to: **Account Settings**
3. Check: **Enable call recording**
4. Verify:
   - Bucket Vendor: AWS S3 Compatible
   - Endpoint URI: `https://s3.eu-west-3.wasabisys.com` (or your endpoint)
   - Bucket Name: `graine` (or your bucket)
   - Access Key ID: Your access key
   - Secret Access Key: Your secret key

### Step 3: Verify WebSocket Configuration

Check if WebSocket is configured:

```bash
sudo docker compose exec feature-server printenv JAMBONZ_RECORD_WS_BASE_URL
```

Should return: `ws://api-server:3000/api/v1`

If not set, check `docker-compose.yaml` - it should have:
```yaml
feature-server:
  environment:
    JAMBONZ_RECORD_WS_BASE_URL: 'ws://api-server:3000/api/v1'
    JAMBONZ_RECORD_WS_USERNAME: 'jambonz'
    JAMBONZ_RECORD_WS_PASSWORD: '5a3e38b5-3188-4936-89c9-fb0df3138b5c'
```

## Known Bug: Audio Interference

**There is a known bug in `jambonz/feature-server`** where:
- Recording interferes with audio during calls
- Feature-server sends wrong `accountSid` to API server
- This causes WebSocket connection issues

### Workaround (If Audio Issues Persist)

**Option 1: Disable Recording Temporarily**

```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET record_all_calls = 0 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a';
"
sudo docker compose restart feature-server
```

**Option 2: Copy Bucket Credentials to Default Account**

The bug causes feature-server to check the default account for bucket credentials. Workaround:

```bash
# Get your account's bucket credentials
BUCKET_CRED=$(sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -N -e "
SELECT bucket_credential 
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a'
ORDER BY created_at DESC 
LIMIT 1;
")

# Copy to default account (workaround for the bug)
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET bucket_credential = '$BUCKET_CRED',
    record_all_calls = 0
WHERE account_sid = '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a';
"

# Keep recording enabled for your account
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET record_all_calls = 1 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a';
"

sudo docker compose restart feature-server
```

## Verification

### Check Recording Status

```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
SELECT 
  account_sid,
  record_all_calls,
  record_format,
  bucket_credential IS NOT NULL as has_bucket_cred
FROM accounts 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a';
"
```

### Test Recording

1. Make a test call
2. Check logs:
   ```bash
   sudo docker compose logs -f feature-server | grep -i record
   ```
3. Check S3 bucket for recording file

### Check for Errors

```bash
# Feature-server recording errors
sudo docker compose logs feature-server | grep -iE "record|recording|error" | tail -20

# API server S3 upload errors
sudo docker compose logs api-server | grep -iE "s3|bucket|upload|error" | tail -20
```

## Permanent Fix

The bug is in `jambonz/feature-server` codebase. The fix requires:
- Feature-server to send correct `accountSid` in WebSocket message
- Not checking default account for bucket credentials

**Location**: `jambonz/feature-server` repository
**Issue**: Feature-server sends default `accountSid` instead of actual call `accountSid`

## Summary

1. ✅ **Enable recording**: `sudo ./fix-recording-complete.sh`
2. ✅ **Verify bucket credentials** in webapp
3. ✅ **Check WebSocket configuration** in docker-compose.yaml
4. ⚠️ **If audio issues**: Use workaround or disable recording until code fix

## Scripts Available

- `fix-recording-complete.sh` - Complete fix (enable + verify)
- `fix-recording-enabled.sh` - Just enable recording
- `check-recording-s3-upload.sh` - Diagnose recording issues
- `diagnose-recording-and-swagger.sh` - Comprehensive diagnostic

