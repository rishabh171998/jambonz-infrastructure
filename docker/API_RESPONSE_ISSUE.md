# API Response Format Issue - Blank Call Records Page

## Problem

When clicking on "Recent Calls" in the webapp, the page shows blank with a JavaScript error:
```
TypeError: Cannot read properties of undefined (reading 'forEach')
```

## Root Cause

The API server (`jambonz/api-server`) is returning a response that doesn't match the OpenAPI specification expected by the frontend.

### API Returns:
```json
{
  "total": 2,
  "page_size": "25",    // ❌ String, should be "batch"
  "page": "1",          // ❌ String, should be number
  "data": [...]
}
```

### Frontend Expects:
```json
{
  "total": 2,
  "batch": 25,          // ✅ Number field named "batch"
  "page": 1,            // ✅ Number
  "data": [...]
}
```

The frontend code tries to access `response.batch.forEach()` but gets `undefined` because the API returns `page_size` instead.

## Impact

- ✅ API is working (returns HTTP 200 with valid data)
- ✅ Database is working (call records are stored)
- ❌ Frontend cannot parse the response (blank page)
- ⚠️ This is a bug in the `jambonz/api-server` codebase

## Solution Options

### Option 1: Update API Server Image (Recommended)
Check if there's a newer version of the API server that fixes this:

```bash
# Pull latest image
docker compose pull api-server

# Restart API server
docker compose up -d api-server
```

### Option 2: Wait for Fix
This needs to be fixed in the `jambonz/api-server` repository. The issue is in the RecentCalls endpoint response format.

### Option 3: Temporary Frontend Workaround (Not Recommended)
Modify the webapp to handle both `page_size` and `batch` fields. This is not recommended for production as it's a workaround for a backend bug.

## Verification

To verify the API response format:

```bash
cd /opt/jambonz-infrastructure/docker
sudo ./debug-api-response.sh
```

Look for:
- ⚠️ Missing expected fields: ['batch']
- ⚠️ Found "page_size" but spec expects "batch"

## Related Issues

- The `lcr` table issue has been fixed (this was causing "Bad Request" errors)
- The API now returns HTTP 200 with data
- The only remaining issue is the response field name mismatch

## Status

- **Issue**: API response format mismatch
- **Severity**: Medium (functionality broken, but API is working)
- **Fix Required**: In `jambonz/api-server` codebase
- **Workaround**: None (requires code change)

