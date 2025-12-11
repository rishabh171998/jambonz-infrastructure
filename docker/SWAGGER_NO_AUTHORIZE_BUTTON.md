# Swagger UI - No Authorize Button

## Problem

Swagger UI loads (HTML is served) but:
- The UI doesn't render (blank page)
- No "Authorize" button appears
- JavaScript files may not be loading

## Root Causes

### 1. Missing JavaScript Files

The Swagger HTML references these files:
- `swagger-ui.css`
- `swagger-ui-bundle.js`
- `swagger-ui-standalone-preset.js`
- `swagger-ui-init.js`

If any of these return 404, Swagger UI won't render.

**Check:**
```bash
sudo ./check-swagger-js-files.sh
```

### 2. Missing Security Definitions

The "Authorize" button only appears if the Swagger JSON includes security definitions.

**Check Swagger JSON:**
```bash
curl http://15.207.113.122:3000/swagger/swagger.json | grep -i security
```

If no output, security definitions are missing.

**Expected format:**
```json
{
  "securityDefinitions": {
    "Bearer": {
      "type": "apiKey",
      "name": "Authorization",
      "in": "header"
    }
  }
}
```

## Solutions

### Solution 1: Check JavaScript Files

Run the diagnostic:
```bash
sudo ./check-swagger-js-files.sh
```

This will show which files are missing (404 errors).

### Solution 2: Use API Directly (Recommended)

Since Swagger UI may not be fully configured, use the API directly:

```bash
# Test your token
curl -H "Authorization: Bearer 38700987-c7a4-4685-a5bb-af378f9734de" \
     http://15.207.113.122:3000/api/v1/Accounts
```

Or use the test script:
```bash
sudo ./test-api-direct.sh
```

### Solution 3: Check Browser Console

1. Open `http://sip.graine.ai:3000/swagger/`
2. Press F12 (Developer Tools)
3. Go to **Console** tab
4. Look for errors like:
   - `Failed to load resource: swagger-ui-bundle.js`
   - `404 Not Found`
   - `CORS policy`

5. Go to **Network** tab
6. Reload page
7. Check which files return 404 (red entries)

### Solution 4: Check API Server Logs

```bash
sudo docker compose logs api-server | grep -i swagger
```

Look for:
- 404 errors for static files
- Errors serving Swagger UI files

## Quick Test

Test if the API works without Swagger UI:

```bash
# List Accounts
curl -H "Authorization: Bearer 38700987-c7a4-4685-a5bb-af378f9734de" \
     http://15.207.113.122:3000/api/v1/Accounts

# If this works, your token is valid and API is working
# Swagger UI is just a convenience tool - not required!
```

## Why This Happens

The `jambonz/api-server` may not be configured to:
1. Serve Swagger UI static files correctly
2. Include security definitions in Swagger JSON

This is a configuration issue in the API server, not your setup.

## Workaround

**Use curl or Postman instead of Swagger UI:**

```bash
# Save your token
export JAMBONZ_TOKEN="38700987-c7a4-4685-a5bb-af378f9734de"
export JAMBONZ_API="http://15.207.113.122:3000/api/v1"

# List Accounts
curl -H "Authorization: Bearer $JAMBONZ_TOKEN" \
     "$JAMBONZ_API/Accounts"

# List Applications
curl -H "Authorization: Bearer $JAMBONZ_TOKEN" \
     "$JAMBONZ_API/Applications"

# Get Account Details
curl -H "Authorization: Bearer $JAMBONZ_TOKEN" \
     "$JAMBONZ_API/Accounts/{account_sid}"
```

This is actually more reliable than Swagger UI for API testing!

