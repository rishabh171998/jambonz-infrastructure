# Fix: "Cannot assign requested address" Error

## Problem

When starting `drachtio-sbc`, you see this error:
```
nta: bind(13.203.223.245:5060;transport=*;maddr=13.203.223.245): Cannot assign requested address
DrachtioController::run: Error calling nta_agent_create
```

## Root Cause

Drachtio is trying to bind directly to the public IP address (`13.203.223.245`), but this IP is not assigned to any network interface on the EC2 instance. AWS uses NAT (Network Address Translation), so the public IP is not directly on the instance.

## Solution

The fix is to:
1. **Bind to all interfaces** using `sip:*` for the `--contact` parameter
2. **Advertise the public IP** using `--external-ip ${HOST_IP}`

This way:
- Drachtio can successfully bind to `0.0.0.0:5060` (all interfaces)
- SIP messages will still show the public IP in Contact headers (via `--external-ip`)

## Updated Configuration

The `drachtio-sbc` service in `docker-compose.yaml` has been updated:

```yaml
command: ["drachtio", "--contact", "sip:*;transport=udp,tcp,tls", "--external-ip", "${HOST_IP}", "--address", "0.0.0.0", "--port", "9022", "--disable-nat-detection"]
```

**Key changes:**
- `--contact sip:*` instead of `--contact sip:${HOST_IP}` (binds to all interfaces)
- `--external-ip ${HOST_IP}` (advertises public IP in SIP messages)

## How to Apply the Fix

1. **Pull the latest changes** (if using git):
   ```bash
   cd /opt/jambonz-infrastructure
   git pull
   ```

2. **Restart drachtio-sbc**:
   ```bash
   cd /opt/jambonz-infrastructure/docker
   docker compose restart drachtio-sbc
   ```

3. **Verify it's working**:
   ```bash
   docker compose logs drachtio-sbc | tail -20
   ```

   You should see:
   - ✅ `starting sip stack on local address sip:*;transport=udp,tcp` (or similar)
   - ✅ `external address: 13.203.223.245`
   - ✅ No "Cannot assign requested address" errors

4. **Check port is listening**:
   ```bash
   sudo netstat -tulpn | grep 5060
   ```

   Should show:
   ```
   tcp  0  0 0.0.0.0:5060  0.0.0.0:*  LISTEN
   udp  0  0 0.0.0.0:5060  0.0.0.0:*
   ```

## Why This Works

- **`sip:*`**: Tells drachtio to bind to all available interfaces (`0.0.0.0`)
- **`--external-ip ${HOST_IP}`**: Tells drachtio what IP to put in SIP Contact headers
- **Result**: Drachtio binds successfully AND advertises the correct public IP

This matches the pattern used in the Packer-based deployments, where they use:
- `LOCAL_IP` for `--contact` (the private IP on the interface)
- `PUBLIC_IP` for `--external-ip` (the public IP to advertise)

In Docker, we use `*` instead of a specific local IP, which is equivalent and works perfectly.

