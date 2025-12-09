# Troubleshooting RTP Port Range Issues

## Problem: Calls Not Reaching After Port Range Change

If calls stopped working after changing RTP port range to 10000-70000, check the following:

## Quick Fix: Revert to Working Configuration

If you need calls working immediately, you can temporarily revert to the smaller port range:

```bash
cd /opt/jambonz-infrastructure/docker

# Edit docker-compose.yaml and change rtpengine ports back to 40000-60000
# Then restart:
sudo docker compose down
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate rtpengine
```

## Check Current Configuration

1. **Verify rtpengine is running:**
```bash
sudo docker compose ps rtpengine
sudo docker compose logs rtpengine | tail -50
```

2. **Check if rtpengine is accessible:**
```bash
# From another container, test connection
sudo docker compose exec sbc-inbound nc -zv rtpengine 22222
```

3. **Check RTP port range in logs:**
```bash
sudo docker compose logs rtpengine | grep -i "port-min\|port-max"
# Should show: --port-min 10000 --port-max 70000
```

4. **Verify security group allows ports:**
```bash
# Check AWS security group allows UDP 10000-70000
aws ec2 describe-security-groups --group-ids sg-xxxxx --query 'SecurityGroups[0].IpPermissions[?FromPort==`10000`]'
```

## Common Issues

### Issue 1: Docker Compose Port Range Limitation

**Symptom:** `invalid containerPort: 10000-70000` error

**Solution:** Docker Compose may not support such large ranges. Use host networking instead:

```yaml
rtpengine:
  network_mode: host
  command: ["rtpengine", "--interface", "private/127.0.0.1", "--interface", "public/0.0.0.0!${HOST_IP}", "--listen-ng", "127.0.0.1:22222", "--port-min", "10000", "--port-max", "70000", "--log-level", "5"]
```

Then update other services to connect via host gateway:
```yaml
JAMBONES_RTPENGINES: '172.10.0.1:22222'  # Bridge gateway IP
```

### Issue 2: rtpengine Not Accessible from Other Containers

**Symptom:** Other containers can't connect to rtpengine

**Solution:** 
- If using host networking, ensure bridge gateway IP is correct
- If using bridge networking, ensure rtpengine is on the same network
- Check: `sudo docker network inspect docker_jambonz`

### Issue 3: Security Group Not Updated

**Symptom:** RTP traffic blocked

**Solution:** Update AWS Security Group:
```bash
# Remove old rule (if exists)
aws ec2 revoke-security-group-ingress --group-id sg-xxxxx --protocol udp --port 40000 --cidr 0.0.0.0/0

# Add new rule
aws ec2 authorize-security-group-ingress \
  --group-id sg-xxxxx \
  --protocol udp \
  --port 10000 \
  --cidr 0.0.0.0/0 \
  --ip-permissions IpProtocol=udp,FromPort=10000,ToPort=70000,IpRanges=[{CidrIp=0.0.0.0/0}]
```

### Issue 4: HOST_IP Not Set

**Symptom:** rtpengine shows wrong IP in logs

**Solution:**
```bash
export HOST_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
sudo HOST_IP="$HOST_IP" docker compose up -d --force-recreate rtpengine
```

## Testing RTP Connectivity

1. **Test from external network:**
```bash
# From your local machine
nc -uv YOUR_EC2_IP 10000
```

2. **Check rtpengine is listening:**
```bash
sudo netstat -tulpn | grep -E "10000|22222"
```

3. **Test NG protocol connection:**
```bash
# From sbc-inbound container
sudo docker compose exec sbc-inbound nc -zv rtpengine 22222
```

## Recommended Configuration

For maximum compatibility, use this configuration:

```yaml
rtpengine:
  image: drachtio/rtpengine:jambonz-test
  restart: always
  command: ["rtpengine", "--interface", "private/172.10.0.11", "--interface", "public/172.10.0.11!${HOST_IP}", "--listen-ng", "172.10.0.11:22222", "--port-min", "10000", "--port-max", "70000", "--log-level", "5"]
  ports:
    - "10000-70000:10000-70000/udp"
  networks:
    jambonz:
      ipv4_address: 172.10.0.11
```

If Docker Compose doesn't support the large range, you may need to:
1. Use host networking (as shown in Issue 1)
2. Or use a smaller published range and let rtpengine handle the rest internally

