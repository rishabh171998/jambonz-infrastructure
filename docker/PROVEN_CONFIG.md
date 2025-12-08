# Using Proven Packer Configuration for drachtio-sbc

## Overview

This configuration uses the **proven Packer approach** for drachtio-sbc binding:
- **Local/Private IP** for `--contact` (binds to the actual network interface)
- **Public IP** for `--external-ip` (advertises in SIP messages)

This matches exactly how the Packer-based deployments work.

## How It Works

### Entrypoint Script

The `drachtio-entrypoint.sh` script:
1. **Fetches LOCAL_IP** (private IP) from:
   - AWS metadata: `http://169.254.169.254/latest/meta-data/local-ipv4`
   - GCP metadata: `http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/ip`
   - Fallback: First non-loopback IP from `hostname -I`

2. **Uses HOST_IP** (public IP) from:
   - Environment variable `HOST_IP` (if set)
   - AWS metadata: `http://169.254.169.254/latest/meta-data/public-ipv4`
   - GCP metadata: `http://169.254.169.254/computeMetadata/v1/instance/network-interfaces/0/access-configs/0/external-ip`
   - Fallback: Uses LOCAL_IP if no public IP found

3. **Builds drachtio command**:
   ```bash
   drachtio \
     --contact "sip:${LOCAL_IP};transport=udp" \
     --contact "sip:${LOCAL_IP};transport=tcp" \
     --contact "sip:${LOCAL_IP};transport=tls" \
     --external-ip "${HOST_IP}" \
     --address "0.0.0.0" \
     --port "9022" \
     --disable-nat-detection
   ```

## Configuration

The `drachtio-sbc` service in `docker-compose.yaml`:
- Uses the entrypoint script instead of inline command
- Mounts the entrypoint script as read-only
- Automatically detects LOCAL_IP and uses HOST_IP from environment

## Benefits

✅ **Proven Configuration**: Matches the working Packer setup exactly  
✅ **Automatic Detection**: No manual IP configuration needed  
✅ **Cloud-Agnostic**: Works on AWS, GCP, and other platforms  
✅ **Reliable Binding**: Uses actual interface IP (not wildcard)  
✅ **Correct SIP Headers**: Advertises public IP in Contact headers  

## Verification

After starting, check the logs:

```bash
docker compose logs drachtio-sbc | grep -i "local_ip\|host_ip\|contact\|external"
```

You should see:
```
drachtio-sbc: Using LOCAL_IP=172.31.13.217 for binding
drachtio-sbc: Using HOST_IP=13.203.223.245 for external-ip
starting sip stack on local address sip:172.31.13.217;transport=udp,tcp (external address: 13.203.223.245)
```

## Comparison with Previous Approach

| Approach | Contact Binding | External IP | Status |
|----------|----------------|-------------|--------|
| **Old (sip:${HOST_IP})** | Tries to bind to public IP | Public IP | ❌ Fails: "Cannot assign requested address" |
| **Wildcard (sip:*)** | Binds to all interfaces | Public IP | ✅ Works, but not proven |
| **Proven (LOCAL_IP)** | Binds to private IP | Public IP | ✅ **Proven, matches Packer** |

## Manual Override (if needed)

If you need to override the auto-detected IPs:

```bash
# Set environment variables before starting
export LOCAL_IP=172.31.13.217  # Your private IP
export HOST_IP=13.203.223.245  # Your public IP

cd /opt/jambonz-infrastructure/docker
docker compose up -d drachtio-sbc
```

The entrypoint script will use these if set, otherwise it will auto-detect.

