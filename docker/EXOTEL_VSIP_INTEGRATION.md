# SIP Trunking Integration Best Practices

This document outlines the best practices for integrating Jambonz with SIP trunking providers (Exotel, Twilio, Voxbone, Simwood, TelecomsXChange, and others).

## Overview

SIP trunking services allow you to connect your Jambonz infrastructure to the PSTN through various providers. Following these best practices ensures optimal call quality, reliability, and security across all providers including Exotel, Twilio, Voxbone, Simwood, TelecomsXChange, and others.

## Best Practices

### 1. Use FQDN for Infrastructure

**Recommendation:** Use Fully Qualified Domain Names (FQDN) instead of IP addresses when:
- Your infrastructure is cloud-based
- You have High Availability (HA) setup
- You're using load balancers

**Benefits:**
- Easier failover and recovery
- Better support for dynamic IP changes
- Improved DNS-based routing

**Configuration:**
- Configure your SIP trunk in Jambonz using FQDN instead of IP addresses
- Ensure DNS records point to your SIP server (drachtio-sbc)

### 2. DNS TTL Configuration

**Recommendation:** Keep DNS TTL between 30–60 seconds for fast recovery

**Why:**
- Shorter TTL allows faster DNS updates during failover scenarios
- Enables quick recovery from infrastructure changes
- Balances between update speed and DNS query load

**Configuration:**
- Set your DNS A/AAAA record TTL to 30-60 seconds
- Example for Route53: Set TTL to 30-60 seconds

### 3. Avoid SIP ALG

**Recommendation:** Disable SIP ALG (Application Layer Gateway) in NAT/firewall appliances

**Why:**
- SIP ALG often interferes with SIP signaling
- Can cause call setup failures
- May modify SIP headers incorrectly

**Configuration:**
- Disable SIP ALG on your router/firewall
- For AWS: Ensure security groups allow direct SIP traffic without ALG
- For GCP: Disable any ALG features in Cloud NAT or firewall rules

### 4. Codec Configuration

**Recommendation:** Use PCMA (G.711 A-law) as primary codec

**Why:**
- PCMA is widely supported and provides good quality
- Low latency and CPU usage
- Standard codec for PSTN interconnects

**Configuration:**
- Configure codec preferences in your VoIP carrier settings
- Set codec order: `PCMA, PCMU, OPUS, G722`
- This is typically configured in the Jambonz web UI under Carrier settings

**Note:** Codec preferences are set per carrier/trunk in the Jambonz application, not in docker-compose.yaml

### 5. Security: TLS + SRTP

**Recommendation:** Use TLS + SRTP for security-sensitive traffic

**Why:**
- Encrypts SIP signaling (TLS)
- Encrypts RTP media (SRTP)
- Prevents eavesdropping and tampering

**Configuration:**
- Enable TLS on drachtio-sbc (port 5061 is already exposed)
- Configure TLS certificates for your SIP domain
- Enable SRTP in carrier settings
- Configure TLS transport in your carrier/trunk settings

### 6. RTP Media Port Range

**Recommendation:** Use RTP media port range 10000–70000 (60K ports)

**Why:**
- Each SIP call uses 2 ports (one for each direction)
- Wide port range ensures compatibility with all SIP trunking providers
- 60K ports support up to 30,000 concurrent calls with buffer
- Covers all provider requirements (Exotel, Twilio, Voxbone, Simwood, TelecomsXChange, etc.)
- Helps avoid NAT-related media drops
- Ensures predictable firewall rules
- Universal compatibility across all major SIP trunking providers

**Current Configuration:**
- rtpengine: Ports 10000-70000 (configured in docker-compose.yaml)
- FreeSWITCH: Ports 20000-20100 (within the rtpengine range)

**Port Calculation:**
- 30,000 concurrent calls × 2 ports per call = 60,000 ports
- Port range 10000-70000 provides 60,000 ports
- Maximum capacity for enterprise-level deployments

### 7. Validate Trunk Reachability

**Recommendation:** Validate trunk reachability before mapping Virtual Numbers (VNs)

**Steps:**
1. Configure your SIP trunk in Jambonz
2. Test outbound calls to verify connectivity
3. Test inbound calls from your carrier
4. Verify SIP trace logs using sngrep or Wireshark
5. Only after successful validation, map your phone numbers/Virtual Numbers

### 8. Firewall/Security Group Configuration

**Required Ports:**

#### SIP Signaling
- UDP 5060: SIP signaling (UDP)
- TCP 5060: SIP signaling (TCP)
- TCP 5061: SIP over TLS (if using TLS)

#### RTP Media
- UDP 10000-70000: RTP media streams

**AWS Security Group Example:**
```bash
# SIP UDP
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol udp \
  --port 5060 \
  --cidr 0.0.0.0/0

# SIP TCP
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 5060 \
  --cidr 0.0.0.0/0

# SIP TLS
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol tcp \
  --port 5061 \
  --cidr 0.0.0.0/0

# RTP Media Range (compatible with all SIP trunking providers: 10000-70000)
aws ec2 authorize-security-group-ingress \
  --group-id $GROUP_ID \
  --protocol udp \
  --port 10000 \
  --cidr 0.0.0.0/0 \
  --ip-permissions IpProtocol=udp,FromPort=10000,ToPort=70000,IpRanges=[{CidrIp=0.0.0.0/0}]
```

**Note:** For production, restrict SIP and RTP to your carrier's IP ranges instead of `0.0.0.0/0`

## Docker Configuration

The docker-compose.yaml has been configured with the following SIP trunking best practices (compatible with all providers):

1. **RTP Port Range:** 10000-70000 (60K ports) - Universal range covering all SIP trunking providers
2. **rtpengine:** Configured with `--port-min 10000 --port-max 70000`
3. **FreeSWITCH:** RTP range set to 20000-20100 (within rtpengine range)
4. **TLS Support:** Port 5061 exposed for SIP over TLS

## Troubleshooting

### SIP Trace Logs

Capture SIP traces for troubleshooting:

```bash
# Using sngrep (if installed)
sngrep -d any

# Using tcpdump
tcpdump -i any -s 0 -w sip_trace.pcap port 5060 or port 5061

# View drachtio logs
docker logs drachtio-sbc
```

### Common Issues

1. **Call Setup Failures:**
   - Check SIP ALG is disabled
   - Verify firewall rules allow SIP traffic
   - Check DNS resolution if using FQDN

2. **One-Way Audio:**
   - Verify RTP port range is correctly configured
   - Check firewall allows bidirectional RTP traffic
   - Verify NAT traversal is working

3. **Codec Mismatch:**
   - Ensure PCMA is in codec list
   - Check codec preferences in carrier settings
   - Verify SDP negotiation in SIP traces

## Provider-Specific Resources

### Exotel
- **Provisioning Support:** Contact your CSM or email: hello@exotel.com
- **Technical Support:** support.exotel.com
- **Documentation:** https://support.exotel.com

### Twilio
- **Documentation:** https://www.twilio.com/docs/voice/sip
- **IP Addresses:** https://www.twilio.com/docs/voice/sip/ip-addresses-trunking
- See [TWILIO_CARRIER_SETUP.md](./TWILIO_CARRIER_SETUP.md) for detailed setup

### Other Providers
- **Voxbone:** https://docs.voxbone.com
- **Simwood:** https://docs.simwood.com
- **TelecomsXChange:** Contact your account manager

## Additional Resources

- [Jambonz Documentation](https://docs.jambonz.org)
- [SIP RFC 3261](https://tools.ietf.org/html/rfc3261)
- [RTP RFC 3550](https://tools.ietf.org/html/rfc3550)

## Configuration Checklist

- [ ] RTP port range configured to 10000-70000 (universal range for all providers)
- [ ] DNS TTL set to 30-60 seconds (if using FQDN)
- [ ] SIP ALG disabled on firewall/router
- [ ] PCMA codec configured as primary
- [ ] TLS + SRTP enabled (if required)
- [ ] Firewall rules configured for SIP (5060/5061) and RTP (10000-70000)
- [ ] Trunk reachability validated
- [ ] SIP trace logging enabled for troubleshooting

