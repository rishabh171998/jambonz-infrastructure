# Twilio vs Exotel: How They Handle Inbound Call Routing

## The Key Difference

### Twilio: Automatic Phone Number Mapping

**How Twilio Works:**
1. When you buy a phone number in Twilio, you configure it with a **SIP URI** (e.g., `sip:your-domain.com`)
2. Twilio's infrastructure **automatically maps** the phone number to your SIP URI
3. When someone calls that phone number:
   - Twilio receives the call
   - Twilio looks up which SIP URI is associated with that phone number
   - Twilio sends INVITE to your SIP server with the **phone number in the Request URI**

**Example:**
```
Phone Number: +15086908019
Configured SIP URI: sip:graineone.sip.graine.ai

When someone calls +15086908019:
  → Twilio sends: INVITE sip:+15086908019@graineone.sip.graine.ai SIP/2.0
```

**Why it works:**
- Twilio maintains an **internal database** mapping phone numbers to SIP URIs
- The phone number is **part of the configuration** in Twilio's system
- Twilio automatically includes it in the Request URI

### Exotel: Manual Destination URI Configuration

**How Exotel Works:**
1. When you configure a trunk in Exotel, you set a **Destination URI** (where to send calls)
2. Exotel uses **internal IDs** for routing within their network
3. By default, Exotel sends these internal IDs in the Request URI
4. You must **explicitly tell Exotel** what phone number to use in the Request URI

**Example (Before Fix):**
```
Phone Number: +918064061518
Destination URI: sip:graineone.sip.graine.ai:5060;transport=tcp

When someone calls +918064061518:
  → Exotel sends: INVITE sip:27270013103585148@15.207.113.122 SIP/2.0
  ❌ (Internal ID, not phone number)
```

**Example (After Fix):**
```
Phone Number: +918064061518
Destination URI: sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp

When someone calls +918064061518:
  → Exotel sends: INVITE sip:+918064061518@15.207.113.122 SIP/2.0
  ✅ (Phone number included)
```

**Why it's different:**
- Exotel's architecture separates:
  - **Routing** (which trunk to use) - uses internal IDs
  - **Destination** (where to send) - uses your SIP URI
- The phone number is **not automatically included** unless you specify it in the Destination URI

## Comparison Table

| Feature | Twilio | Exotel |
|---------|--------|--------|
| **Phone Number Mapping** | Automatic (built into platform) | Manual (via Destination URI) |
| **Request URI Format** | `sip:+PHONE@your-domain.com` | `sip:INTERNAL_ID@your-ip` (default) |
| **Configuration Location** | Phone Number settings | Trunk Destination URI |
| **Requires Phone Number in URI?** | ✅ Automatic | ❌ Must specify manually |
| **Internal Routing** | Uses phone number directly | Uses internal IDs |

## Why This Design Difference?

### Twilio's Approach
- **Phone number-centric**: Phone numbers are first-class entities
- **Simpler for users**: Just configure the SIP URI once
- **Automatic**: Platform handles the mapping

### Exotel's Approach
- **Trunk-centric**: Focuses on trunk configuration
- **More flexible**: Can route multiple numbers through one trunk
- **Requires explicit configuration**: More control, but more setup

## Configuration Examples

### Twilio Configuration

**In Twilio Dashboard:**
1. Go to Phone Numbers → Manage → Active Numbers
2. Click on your phone number
3. Set "Voice & Fax" → "A CALL COMES IN" → "Webhook/TwiML Bin"
4. Or set "SIP" → "SIP URI": `sip:graineone.sip.graine.ai`

**Result:**
- Twilio automatically sends: `INVITE sip:+15086908019@graineone.sip.graine.ai`

### Exotel Configuration

**In Exotel Dashboard:**
1. Go to Trunk Configuration
2. Find "Destination URI" or "SIP URI"
3. Set to: `sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp`

**Result:**
- Exotel sends: `INVITE sip:+918064061518@15.207.113.122`

## How Jambonz Handles Both

Jambonz's `sbc-inbound` service:
1. Receives the INVITE
2. Extracts the phone number from the **Request URI**
3. Looks up the phone number in the `phone_numbers` table
4. Routes to the associated application

**Works with:**
- ✅ Twilio: `sip:+15086908019@domain.com` → Finds `+15086908019`
- ✅ Exotel (fixed): `sip:+918064061518@domain.com` → Finds `+918064061518`
- ❌ Exotel (broken): `sip:27270013103585148@domain.com` → Can't find number

## Summary

**Twilio:**
- ✅ Automatically includes phone number in Request URI
- ✅ Just configure SIP URI once
- ✅ Phone number is part of Twilio's phone number object

**Exotel:**
- ⚠️ Must include phone number in Destination URI manually
- ⚠️ More configuration required
- ✅ More flexible for complex routing scenarios

**The Fix:**
For Exotel, you must include the phone number in the Destination URI:
```
sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp
```

This tells Exotel: "When routing calls to this trunk, put `+918064061518` in the Request URI."

