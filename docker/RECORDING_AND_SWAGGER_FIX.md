# Recording and Swagger Issues - Fix Guide

## Issues Identified

1. **Recording not saving to bucket**
2. **Recording audio issue (still present)**
3. **Swagger page not opening**

## Issue 1: Recording Not Saving to Bucket

### Possible Causes:
1. Bucket credentials not configured in account
2. WebSocket connection between feature-server and api-server failing
3. S3 permissions incorrect
4. Recording format mismatch

### Diagnostic Steps:

Run the diagnostic script:
```bash
sudo ./diagnose-recording-and-swagger.sh
```

### Fix Steps:

1. **Verify Bucket Credentials:**
   - Go to webapp → Account Settings
   - Check "Enable call recording"
   - Verify:
     - Bucket Vendor (AWS S3 Compatible)
     - Endpoint URI
     - Bucket Name
     - Access Key ID
     - Secret Access Key

2. **Check Recording WebSocket:**
   - Feature-server should have: `JAMBONZ_RECORD_WS_BASE_URL: 'ws://api-server:3000/api/v1'`
   - API server should be listening on port 3000

3. **Check Logs:**
   ```bash
   sudo docker compose logs -f feature-server | grep -i record
   sudo docker compose logs -f api-server | grep -i "s3\|bucket\|upload"
   ```

4. **Verify S3 Permissions:**
   - Access Key should have: `s3:PutObject`, `s3:GetObject` permissions
   - Bucket should exist and be accessible

## Issue 2: Recording Audio Issue

This is the known bug where recording interferes with audio during calls.

### Current Status:
- Bug exists in `jambonz/feature-server` codebase
- Feature-server sends wrong `accountSid` to API server for recording
- Workaround: Disable recording until code fix is applied

### Temporary Workaround:

Disable recording for the account:
```bash
sudo docker compose exec -T mysql mysql -ujambones -pjambones jambones -e "
UPDATE accounts 
SET record_all_calls = 0 
WHERE account_sid != '9351f46a-8a8a-4b4b-9c9c-1a1a1a1a1a1a';
"
sudo docker compose restart feature-server
```

### Permanent Fix:
- Requires code fix in `jambonz/feature-server`
- Bug location: Feature-server sends default `accountSid` instead of actual call `accountSid` in WebSocket message

## Issue 3: Swagger Not Opening

### Possible Causes:
1. Port 3000 not exposed in security group
2. API server not listening on 0.0.0.0
3. API server not running
4. Firewall blocking port 3000

### Diagnostic Steps:

1. **Check API Server Status:**
   ```bash
   sudo docker compose ps api-server
   sudo docker compose logs api-server | tail -20
   ```

2. **Check Port Mapping:**
   ```bash
   sudo docker compose ps | grep api-server
   ```
   Should show: `0.0.0.0:3000->3000/tcp`

3. **Check Listening:**
   ```bash
   sudo docker compose exec api-server netstat -tlnp | grep 3000
   ```
   Should show: `0.0.0.0:3000`

4. **Test from Host:**
   ```bash
   curl -I http://localhost:3000/swagger
   ```

5. **Test from External:**
   ```bash
   curl -I http://<HOST_IP>:3000/swagger
   ```

### Fix Steps:

1. **Verify Security Group:**
   - AWS Security Group should allow:
     - Inbound: TCP 3000 from your IP or 0.0.0.0/0 (for testing)

2. **Verify API Server Binding:**
   - API server should listen on `0.0.0.0:3000` (not `127.0.0.1:3000`)
   - Check `docker-compose.yaml`:
     ```yaml
     api-server:
       ports:
         - "3000:3000"
       environment:
         HTTP_PORT: 3000
     ```

3. **Restart API Server:**
   ```bash
   sudo docker compose restart api-server
   ```

4. **Access Swagger:**
   - URL: `http://<HOST_IP>:3000/swagger`
   - Requires Bearer token authentication
   - Generate token using `create-admin-token.sql`

## Quick Fix Script

Run the automated fix script:
```bash
sudo ./fix-recording-and-swagger.sh
```

This script will:
1. Check recording WebSocket configuration
2. Verify API server network binding
3. Check account bucket credentials
4. Restart services
5. Test swagger accessibility

## Verification

After applying fixes:

1. **Test Recording:**
   - Make a test call
   - Check logs for recording activity
   - Verify file appears in S3 bucket

2. **Test Swagger:**
   - Open: `http://<HOST_IP>:3000/swagger`
   - Should see Swagger UI
   - Requires authentication token

3. **Check Logs:**
   ```bash
   sudo docker compose logs -f feature-server api-server | grep -iE "record|swagger|error"
   ```

## Common Errors

### Error: "invalid cfg - missing JAMBONZ_RECORD_WS_BASE_URL"
- **Fix:** Ensure `JAMBONZ_RECORD_WS_BASE_URL` is set in feature-server environment

### Error: "Cannot connect to swagger"
- **Fix:** Check security group, verify port 3000 is open

### Error: "Recording not saving"
- **Fix:** Verify bucket credentials, check S3 permissions, check logs for upload errors

### Error: "No audio during recording"
- **Fix:** Known bug - disable recording until code fix is applied

