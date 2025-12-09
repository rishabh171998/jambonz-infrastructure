# Exotel Trunk Form - Step-by-Step Guide

## Form Fields Explained

### 1. Trunk Details

**Trunk Name:**
```
Exophone
```
- Use any descriptive name
- This is just for your reference

**Alias:**
```
(Leave empty or use same as Trunk Name)
```
- Optional field
- Can be left blank

### 2. Whitelist IPs

**IP Address:**
```
15.207.113.122
```
- This is your Jambonz server's public IP
- Get it from: `grep HOST_IP docker/.env` or AWS EC2 console

**Subnet Mask:**
```
32
```
- `/32` means "this exact IP address"
- Use `32` for single IP whitelisting

**Note:** You can add multiple IPs if you have multiple Jambonz servers.

### 3. Destination URIs (CRITICAL SECTION)

This is where you configure where Exotel sends calls. **The phone number must be included here.**

#### Option 1: Using the Form Fields (If Available)

**Transport Protocol:**
```
TCP
```
- Select `TCP` (recommended for simplicity)
- Or `TLS` if you want encryption

**Destination IP/FQDN:**
```
+918064061518@graineone.sip.graine.ai
```
- ⚠️ **IMPORTANT:** Include the phone number with `@` symbol
- Format: `+PHONE_NUMBER@YOUR_FQDN`
- This tells Exotel to put the phone number in the Request URI

**Destination Port:**
```
5060
```
- Port `5060` for TCP
- Port `443` if using TLS

#### Option 2: If Form Doesn't Support Phone Number in FQDN Field

If the form doesn't allow `+918064061518@graineone.sip.graine.ai` in the FQDN field, you may need to:

1. **Enter just the FQDN:**
   ```
   graineone.sip.graine.ai
   ```

2. **Look for an additional field** like:
   - "User Part"
   - "Username"
   - "Phone Number"
   - "Request URI User"

3. **Or check for "Advanced Settings"** where you can specify the full URI:
   ```
   sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp
   ```

## Complete Configuration Example

### Basic Configuration (TCP)

```
Trunk Name: Exophone
Alias: (empty)

Whitelist IPs:
  IP Address: 15.207.113.122
  Subnet Mask: 32

Destination URIs:
  Transport Protocol: TCP
  Destination IP/FQDN: +918064061518@graineone.sip.graine.ai
  Destination Port: 5060
```

### Alternative: If Phone Number Field is Separate

```
Trunk Name: Exophone
Alias: (empty)

Whitelist IPs:
  IP Address: 15.207.113.122
  Subnet Mask: 32

Destination URIs:
  Transport Protocol: TCP
  Destination IP/FQDN: graineone.sip.graine.ai
  Destination Port: 5060
  Phone Number/User Part: +918064061518
```

### TLS Configuration (If Needed)

```
Trunk Name: Exophone
Alias: (empty)

Whitelist IPs:
  IP Address: 15.207.113.122
  Subnet Mask: 32

Destination URIs:
  Transport Protocol: TLS
  Destination IP/FQDN: +918064061518@graineone.sip.graine.ai
  Destination Port: 443
```

## Verification After Saving

After creating the trunk, verify the configuration:

1. **Check the Destination URI** in Exotel dashboard
   - Should show: `sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp`
   - Or similar format with phone number included

2. **Test with a call:**
   ```bash
   sudo docker compose logs -f drachtio-sbc | grep "INVITE sip:"
   ```

3. **Expected result:**
   ```
   INVITE sip:+918064061518@15.207.113.122 SIP/2.0
   ```
   ✅ Should contain your phone number

4. **If you still see:**
   ```
   INVITE sip:27270013103585148@15.207.113.122 SIP/2.0
   ```
   ❌ Phone number not included - need to fix Destination URI

## Troubleshooting

### Problem: Form doesn't accept `+918064061518@graineone.sip.graine.ai`

**Solution 1:** Try without the `+`:
```
918064061518@graineone.sip.graine.ai
```

**Solution 2:** Try with local format:
```
08064061518@graineone.sip.graine.ai
```

**Solution 3:** Look for a separate "User" or "Phone Number" field

### Problem: Can't find where to add phone number

**Check:**
1. Look for "Advanced Settings" or "Additional Options"
2. Check if there's a "Request URI" field
3. Look for "User Part" or "Username" field
4. Check Exotel documentation for your specific dashboard version

### Problem: Form validation error

**Common issues:**
- FQDN field might not accept `@` symbol
- Try entering FQDN and phone number separately if fields exist
- Contact Exotel support if form doesn't support phone number in URI

## Key Points to Remember

1. ✅ **Phone number MUST be in the Destination URI**
   - Either: `+918064061518@graineone.sip.graine.ai`
   - Or in a separate "User" field if available

2. ✅ **Whitelist your Jambonz IP**
   - IP: `15.207.113.122`
   - Subnet: `32`

3. ✅ **Use TCP 5060** (simplest) or TLS 443 (secure)

4. ✅ **Verify after saving** - check logs to confirm phone number appears in INVITE

## After Configuration

Once the trunk is created:

1. **Assign phone number to trunk** (if not done automatically)
2. **Test inbound call**
3. **Monitor logs:**
   ```bash
   sudo docker compose logs -f drachtio-sbc
   ```
4. **Look for:**
   - ✅ `INVITE sip:+918064061518@...` (success)
   - ❌ `INVITE sip:27270013103585148@...` (still broken)

If you still see internal IDs, the Destination URI format needs adjustment.

