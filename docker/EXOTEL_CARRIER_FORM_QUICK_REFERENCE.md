# Exotel vSIP - Jambonz Carrier Form Quick Reference

## Form Fields to Fill

### Basic Information
```
Carrier name: Exotel vSIP - Test
Select a predefined carrier: None
Active: ✅ Checked
```

### General Tab
```
E.164 syntax: ✅ Prepend a leading +
Require SIP Register: ❌ Unchecked
Tech prefix: (empty)
SIP Diversion Header: (empty)
Outbound SIP Proxy: (empty)
```

### SIP Gateways Section

**Click "+" to add each gateway:**

#### Gateway 1 (Signaling - Primary)
```
Network address: pstn.in2.exotel.com
Port: 5070
Netmask: 32
Inbound: ✅
Outbound: ✅
Protocol: tcp
```

#### Gateway 2 (Signaling - Backup)
```
Network address: pstn.in4.exotel.com
Port: 5070
Netmask: 32
Inbound: ✅
Outbound: ✅
Protocol: tcp
```

#### Gateway 3 (Media - Mumbai DC)
```
Network address: 182.76.143.61
Port: 5060
Netmask: 32
Inbound: ✅
Outbound: ❌
Protocol: udp
```

#### Gateway 4 (Media - Mumbai DC Backup)
```
Network address: 122.15.8.184
Port: 5060
Netmask: 32
Inbound: ✅
Outbound: ❌
Protocol: udp
```

### Inbound Tab
```
Allowed IP Addresses (Static IP Whitelist):

Click "+" to add each IP:

1. Network address: 182.76.143.61
   Netmask: 32

2. Network address: 122.15.8.184
   Netmask: 32

3. Network address: 14.194.10.247
   Netmask: 32

4. Network address: 61.246.82.75
   Netmask: 32
```

### Outbound & Registration Tab
```
From Domain: graine1m.pstn.exotel.com
Register Username: (empty)
Register Password: (empty)
```

## Important: RTP Port Range

**Current Jambonz RTP range:** 40000-40100 (too small!)

**Exotel requires:** 10000-40000

**Action needed:** Update `docker-compose.yaml` rtpengine ports to:
```yaml
ports:
  - "10000-20000:10000-20000/udp"
```

Or use a range that overlaps with Exotel's 10000-40000.

## After Configuration

1. **Provide your Jambonz public IP to Exotel** for whitelisting
2. **Update AWS Security Group** to allow:
   - TCP 5070 (SIP signaling)
   - TCP 443 (if using TLS)
   - UDP 10000-40000 (RTP media)
3. **Test inbound call** from Exotel
4. **Test outbound call** to Exotel

