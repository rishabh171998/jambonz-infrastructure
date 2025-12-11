# PCAP Download Requires Homer Configuration

## Issue

PCAP downloads are returning "Bad Request" (400) errors because **Homer is not configured** in your Jambonz setup.

## Root Cause

The PCAP endpoint in `jambonz-api-server` requires Homer (SIP capture system) to be configured. Looking at the API code:

```javascript
router.get('/:call_id/:method/pcap', async(req, res) => {
  const token = await getHomerApiKey(logger);
  if (!token) return res.sendStatus(400, {msg: 'Failed to get Homer API token; check server config'});
  // ...
});
```

If Homer environment variables are not set, the API returns a 400 error.

## Solution Options

### Option 1: Configure Homer (Recommended for PCAP functionality)

Add Homer configuration to your `docker-compose.yaml`:

```yaml
api-server:
  environment:
    <<: *common-variables
    HTTP_PORT: 3000
    HOMER_BASE_URL: 'http://homer:9080'  # Your Homer instance URL
    HOMER_USERNAME: 'admin'              # Homer username
    HOMER_PASSWORD: 'your-password'      # Homer password
    # ... other env vars
```

Then restart the API server:
```bash
sudo docker compose restart api-server
```

### Option 2: Disable PCAP Button (If Homer not needed)

If you don't need PCAP functionality, you can hide the PCAP download button in the webapp. The current code already handles the error gracefully by showing "PCAP unavailable" instead of crashing.

### Option 3: Use Alternative PCAP Source

If you have PCAP files stored elsewhere (S3, etc.), you could modify the API endpoint to fetch from that source instead of Homer.

## Current Status

- ✅ Code is correctly calling: `/Accounts/{sid}/RecentCalls/{call_sid}/invite/pcap`
- ✅ Error handling shows "PCAP unavailable" instead of crashing
- ❌ Homer is not configured, so PCAP downloads will fail with 400 error

## Verification

To check if Homer is configured:

```bash
cd /opt/jambonz-infrastructure/docker
sudo ./check-homer-config.sh
```

## References

- Homer Project: https://github.com/sipcapture/homer
- Jambonz API Server: https://github.com/jambonz/jambonz-api-server

