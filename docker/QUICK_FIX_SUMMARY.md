# Quick Fix Summary

## Issues Found

1. ✅ **Recording Disabled**: `record_all_calls: 0`
2. ⚠️ **Swagger HTTP 301**: Redirect issue
3. ✅ **Port Mapping**: Correct in docker-compose.yaml

## Fix 1: Enable Recording

**Problem**: Recording is disabled for your account (`record_all_calls: 0`)

**Solution**: Run this script:
```bash
sudo ./fix-recording-enabled.sh
```

Or manually:
```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET record_all_calls = 1 
WHERE account_sid = 'bed525b4-af09-40d2-9fe7-cdf6ae577c69';
"
sudo docker compose restart feature-server
```

**Note**: After enabling, if you still experience audio issues during recording, this is a known bug in `jambonz/feature-server` that requires a code fix.

## Fix 2: Swagger HTTP 301 Redirect

**Problem**: Swagger returns HTTP 301 (redirect)

**Solution**: Try these URLs:

1. **With trailing slash** (most likely):
   ```
   http://15.207.113.122:3000/swagger/
   ```

2. **Without trailing slash**:
   ```
   http://15.207.113.122:3000/swagger
   ```

3. **API endpoint**:
   ```
   http://15.207.113.122:3000/api/v1
   ```

**Diagnostic**: Run this to test all URLs:
```bash
sudo ./fix-swagger-301.sh
```

## Verification

After enabling recording:

1. **Make a test call**
2. **Check logs**:
   ```bash
   sudo docker compose logs -f feature-server | grep -i record
   ```
3. **Check S3 bucket** for recording files

## Current Status

- ✅ Bucket credentials: Configured
- ✅ Recording WebSocket: Configured
- ❌ Recording enabled: **NO** (needs fix)
- ⚠️ Swagger: HTTP 301 (try trailing slash)

