# Blank Swagger Page - Fix Guide

## Problem

Accessing `http://sip.graine.ai:3000/swagger/` shows a blank white page.

## Common Causes

1. **JavaScript not loading** - Swagger UI JS files failing to load
2. **CORS issues** - Cross-origin requests blocked
3. **Proxy/Load Balancer** - Interfering with requests
4. **DNS/Network** - `sip.graine.ai` not resolving correctly
5. **API Server** - Not serving Swagger UI correctly

## Quick Diagnostic

Run the diagnostic script:
```bash
sudo ./diagnose-blank-swagger.sh
```

## Solutions

### Solution 1: Use IP Address Directly

If `sip.graine.ai` is behind a proxy that's interfering:

```
http://15.207.113.122:3000/swagger/
```

### Solution 2: Check Browser Console

1. Open browser Developer Tools (F12)
2. Go to **Console** tab
3. Look for JavaScript errors
4. Go to **Network** tab
5. Reload page and check for failed requests (red entries)

Common errors:
- `Failed to load resource` - Network issue
- `CORS policy` - CORS blocking
- `404 Not Found` - Missing files

### Solution 3: Check if Swagger JSON is Loading

Test if the Swagger specification is accessible:

```bash
curl http://15.207.113.122:3000/swagger/swagger.json
```

Or in browser:
```
http://sip.graine.ai:3000/swagger/swagger.json
```

If this returns JSON, the API server is working but the UI isn't loading.

### Solution 4: Restart API Server

```bash
sudo docker compose restart api-server
```

Wait 5-10 seconds, then try again.

### Solution 5: Check Proxy Configuration

If `sip.graine.ai` is behind nginx or another proxy:

1. Check if proxy is stripping headers
2. Check if proxy is blocking JavaScript files
3. Verify proxy is forwarding to `localhost:3000` correctly

### Solution 6: Try Alternative Endpoints

1. **Swagger UI (with trailing slash)**:
   ```
   http://sip.graine.ai:3000/swagger/
   ```

2. **Swagger UI (without trailing slash)**:
   ```
   http://sip.graine.ai:3000/swagger
   ```

3. **API Root**:
   ```
   http://sip.graine.ai:3000/api/v1
   ```

4. **Direct IP**:
   ```
   http://15.207.113.122:3000/swagger/
   ```

## Debugging Steps

### Step 1: Check API Server Logs

```bash
sudo docker compose logs -f api-server
```

Look for:
- Swagger-related errors
- 404 errors for JS/CSS files
- CORS errors

### Step 2: Test from Server

SSH into the server and test locally:

```bash
curl -I http://localhost:3000/swagger/
```

Should return `HTTP/1.1 200 OK`

### Step 3: Check DNS Resolution

```bash
dig sip.graine.ai
```

Verify it resolves to `15.207.113.122`

### Step 4: Check Security Group

Ensure AWS Security Group allows:
- **Inbound**: TCP port 3000 from your IP or 0.0.0.0/0

### Step 5: Check Browser Network Tab

1. Open Developer Tools (F12)
2. Go to **Network** tab
3. Reload the page
4. Check which requests are failing:
   - `swagger.json` - Should return 200
   - `swagger-ui.css` - Should return 200
   - `swagger-ui-bundle.js` - Should return 200

## Quick Fix Script

Run the automated fix:
```bash
sudo ./fix-blank-swagger.sh
```

This will:
1. Restart API server
2. Test Swagger endpoint
3. Check logs
4. Provide troubleshooting steps

## Expected Behavior

When Swagger is working correctly:
- Page loads with Swagger UI interface
- Shows API endpoints
- Requires Bearer token authentication
- Can test API calls directly

## If Still Not Working

1. **Check API Server Version**:
   ```bash
   sudo docker compose exec api-server node --version
   ```

2. **Pull Latest Image**:
   ```bash
   sudo docker compose pull api-server
   sudo docker compose up -d api-server
   ```

3. **Check for Updates**:
   The Swagger endpoint might have changed in newer versions of jambonz/api-server

4. **Alternative**: Use API directly with curl/Postman instead of Swagger UI

