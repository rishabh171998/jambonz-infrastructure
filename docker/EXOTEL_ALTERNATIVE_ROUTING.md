# Exotel Alternative Routing Solutions

## Problem

Exotel Destination URI cannot be changed, and Exotel sends internal IDs instead of phone numbers:
```
INVITE sip:284700441224015426@15.207.113.122
```

Jambonz needs the phone number in the Request URI to route calls.

## Alternative Solutions

### Option 1: Phone Number-Level Configuration in Exotel

**Check if Exotel allows phone number-specific routing:**

1. Go to **Phone Numbers** section in Exotel dashboard
2. Click on `+918064061518`
3. Look for:
   - "SIP URI" or "Destination URI" field
   - "Routing" or "Call Routing" settings
   - "SIP Settings" or "Trunk Settings"
4. If available, configure the phone number's destination separately from the trunk

**If this exists:**
- Set phone number's SIP URI to: `sip:+918064061518@graineone.sip.graine.ai:5060;transport=tcp`
- This might override the trunk-level Destination URI

### Option 2: Use Carrier Application Routing in Jambonz

**Configure Jambonz to route all calls from Exotel to a specific application:**

1. In Jambonz webapp, go to **Carriers → Exotel**
2. Find **"Application"** or **"Default Application"** field
3. Set it to your application
4. This routes ALL calls from Exotel to that application, regardless of Request URI

**Limitation:** All calls from Exotel go to the same application (can't route by phone number)

### Option 3: IP-Based Routing with Caller ID

**Use the `From` header or other SIP headers for routing:**

1. Check if Exotel includes the phone number in:
   - `From` header: `<sip:100@15.207.113.122>`
   - `P-Asserted-Identity` header
   - `Remote-Party-ID` header
   - Custom headers

2. Modify Jambonz routing logic to extract phone number from these headers instead of Request URI

**Note:** This requires code changes to Jambonz `sbc-inbound` service.

### Option 4: Contact Exotel Support

**Ask Exotel support:**

1. **Question:** "How do I configure the Request URI to include the phone number when sending calls to my SIP server?"

2. **Explain:** "Currently, Exotel sends internal IDs like `sip:284700441224015426@...` but my SIP server needs the actual phone number like `sip:+918064061518@...` in the Request URI to route calls correctly."

3. **Request:** 
   - Is there a way to configure this at the phone number level?
   - Is there a different field or setting?
   - Can this be configured via API?

### Option 5: Use Exotel API to Configure

**Check if Exotel API allows setting Destination URI per phone number:**

1. Review Exotel API documentation
2. Look for endpoints like:
   - `PUT /v1/PhoneNumbers/{PhoneNumberSid}`
   - `PUT /v1/Trunks/{TrunkSid}/PhoneNumbers/{PhoneNumberSid}`
3. Set `sip_uri` or `destination_uri` via API

### Option 6: Custom Jambonz Routing Script

**Create a custom routing script that maps Exotel internal IDs to phone numbers:**

1. Create a mapping table in Jambonz database:
   ```sql
   CREATE TABLE exotel_id_mapping (
     exotel_internal_id VARCHAR(255) PRIMARY KEY,
     phone_number VARCHAR(20),
     application_sid CHAR(36)
   );
   ```

2. Modify `sbc-inbound` to:
   - Check if Request URI contains Exotel internal ID
   - Look up phone number in mapping table
   - Route to application

**Note:** This requires significant code changes and maintenance.

## Recommended Approach

### Step 1: Contact Exotel Support (First Priority)

**Email/Support Ticket Template:**

```
Subject: Request URI Configuration for SIP Trunking

Hello Exotel Support,

I'm configuring a SIP trunk to route calls to my SIP server (Jambonz). 
Currently, Exotel is sending internal IDs in the Request URI:

  INVITE sip:284700441224015426@my-server.com

However, my SIP server needs the actual phone number in the Request URI 
to route calls correctly:

  INVITE sip:+918064061518@my-server.com

Questions:
1. Is there a way to configure the Request URI format at the phone number level?
2. Can I set a different Destination URI per phone number?
3. Is this configurable via API?
4. Are there any other settings I should check?

Trunk Details:
- Trunk ID: trmum1b5bb8024884011b3b019c9
- Phone Number: +918064061518
- Current Destination URI: sip:graineone.sip.graine.ai:5060;transport=tcp

Thank you for your assistance.
```

### Step 2: Check Phone Number Settings

While waiting for support, check:

1. **Phone Number Details Page:**
   - Go to Phone Numbers → `+918064061518`
   - Look for "SIP Settings", "Routing", or "Destination" fields
   - Check if there's a way to override trunk-level settings

2. **Trunk Advanced Settings:**
   - Look for "Advanced" or "Additional Settings"
   - Check for "Request URI Format" or "SIP Header Configuration"

### Step 3: Temporary Workaround (If Needed)

If you need calls working immediately:

1. **Use Carrier-Level Application Routing:**
   - Set Exotel carrier's default application in Jambonz
   - All calls from Exotel route to that application
   - Use application logic to determine routing based on other headers

2. **Monitor for Phone Number in Other Headers:**
   ```bash
   sudo docker compose logs -f drachtio-sbc | grep -A 20 "INVITE sip:"
   ```
   - Check if phone number appears in `From`, `To`, or other headers
   - If yes, we can modify routing logic

## Next Steps

1. ✅ **Contact Exotel Support** - This is the proper solution
2. ✅ **Check Phone Number Settings** - Look for per-number configuration
3. ✅ **Check Exotel API** - See if API allows configuration
4. ⚠️ **Temporary Workaround** - Use carrier-level routing if needed

## Why This Matters

Jambonz's routing works like this:
1. Receives INVITE: `sip:284700441224015426@...`
2. Extracts user part: `284700441224015426`
3. Looks up in `phone_numbers` table: `SELECT * FROM phone_numbers WHERE number = '284700441224015426'`
4. ❌ Not found → 404 Not Found

If Exotel sends: `sip:+918064061518@...`
1. Extracts user part: `+918064061518`
2. Looks up in `phone_numbers` table: `SELECT * FROM phone_numbers WHERE number = '+918064061518'`
3. ✅ Found → Routes to application

**The phone number MUST be in the Request URI for Jambonz to route correctly.**

