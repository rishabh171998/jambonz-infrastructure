# PCAP Download Fix Summary

## Issue
PCAP downloads return "400 Bad Request" error.

## Root Causes Identified

1. **Homer Not Configured**: The API endpoint requires Homer to be configured. If Homer environment variables are missing, it returns 400.

2. **Call ID Format**: Homer stores calls by SIP Call-ID (`sip_callid`), not by Jambonz `call_sid` (UUID). The code needs to use `sip_callid`.

## Fixes Applied

### 1. Updated pcap.tsx Component
- Changed to use `call.sip_callid || call.call_sid` (preferring sip_callid)
- Added better error handling for Homer configuration errors
- Shows clear error messages instead of just "Bad Request"

### 2. Added Homer to docker-compose.yaml
- Added `homer` service (webapp on port 9080)
- Added `heplify-server` service (SIP capture on port 9060 UDP)
- Updated `api-server` with Homer environment variables:
  - `HOMER_BASE_URL: 'http://homer:9080'`
  - `HOMER_USERNAME: 'admin'`
  - `HOMER_PASSWORD: 'admin123'`

## Next Steps

1. **Run Homer setup:**
   ```bash
   cd /opt/jambonz-infrastructure/docker
   sudo ./setup-homer.sh
   ```

2. **Rebuild webapp with fixes:**
   ```bash
   sudo docker compose build webapp
   sudo docker compose restart webapp
   ```

3. **Verify Homer is working:**
   - Check Homer UI: http://localhost:9080 (or http://15.207.113.122:9080)
   - Username: admin, Password: admin123
   - Check API server logs: `sudo docker compose logs api-server | grep -i homer`

4. **Test PCAP download:**
   - Make a test call
   - Check if it appears in Homer
   - Try downloading PCAP from Recent Calls page

## Important Notes

- **Homer needs SIP traffic**: For PCAP files to be available, SIP traffic must be sent to heplify-server (port 9060 UDP) using HEP (Homer Encapsulation Protocol)
- **Call ID format**: The API accepts `sip_callid` (SIP Call-ID header) which Homer uses to look up calls
- **400 Error**: If you still get 400 after setup, check:
  - Homer services are running: `sudo docker compose ps homer heplify-server`
  - API server has Homer env vars: `sudo docker compose exec api-server printenv | grep HOMER`
  - Homer is accessible: `curl http://localhost:9080`

