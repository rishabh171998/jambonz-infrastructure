# Fix NXDOMAIN Error for sip.graine.ai

## Problem

You're getting `NXDOMAIN` when trying to resolve `sip.graine.ai`:

```
;; status: NXDOMAIN
```

This means the DNS record doesn't exist in Route53.

## Root Cause

You created a wildcard record `*.sip.graine.ai`, but:
- ✅ Wildcard `*.sip.graine.ai` matches: `account1.sip.graine.ai`, `account2.sip.graine.ai`, etc.
- ❌ Wildcard `*.sip.graine.ai` does NOT match: `sip.graine.ai` (the base domain)

## Solution: Create Both Records

You need to create **TWO** DNS records in Route53:

### Record 1: Base Domain (Required)

**Route53 Console:**
1. Go to **Route53 → Hosted zones → graine.ai**
2. Click **Create record**
3. Configure:
   - **Record name**: `sip` (creates `sip.graine.ai`)
   - **Record type**: `A`
   - **Value**: `13.203.223.245`
   - **TTL**: `300`
4. Click **Create records**

### Record 2: Wildcard for Subdomains (Already Created)

You already have this:
- **Record name**: `*.sip` (covers `*.sip.graine.ai`)
- **Record type**: `A`
- **Value**: `13.203.223.245`
- **TTL**: `300`

## Verify After Creating

### Step 1: Query Route53 Nameservers Directly

Route53 nameservers for `graine.ai` are:
- `ns-1609.awsdns-09.co.uk`
- `ns-1533.awsdns-63.org`
- `ns-630.awsdns-14.net`
- `ns-1.awsdns-00.com`

Query directly to bypass cache:

```bash
# Query Route53 nameserver directly
dig @ns-1609.awsdns-09.co.uk sip.graine.ai

# Or try another nameserver
dig @ns-1533.awsdns-63.org sip.graine.ai
```

If this works, it means the record exists but your local DNS cache hasn't updated yet.

### Step 2: Clear DNS Cache (macOS)

```bash
# Flush DNS cache on macOS
sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder

# Then test again
dig sip.graine.ai
```

### Step 3: Use Public DNS to Test Immediately

Your ISP's DNS server is caching the old NXDOMAIN. Use a public DNS server to test immediately:

```bash
# Use Google's public DNS (bypasses your ISP's cache)
dig @8.8.8.8 sip.graine.ai
# Should return: sip.graine.ai. 300 IN A 13.203.223.245

# Or Cloudflare DNS
dig @1.1.1.1 sip.graine.ai

# Or Quad9 DNS
dig @9.9.9.9 sip.graine.ai
```

**If these work, your DNS record is correct!** The issue is just your ISP's DNS cache.

### Step 4: Wait for ISP DNS Cache to Expire

Your ISP's DNS server (`2405:201:401a:d1eb::c0a8:1d01`) has cached the NXDOMAIN response. This can take:
- **Minimum**: 5-10 minutes
- **Maximum**: Up to the NXDOMAIN TTL (could be hours)

**The record is working correctly** - SIP devices will be able to resolve it once their DNS caches update or if they use different DNS servers.

### Step 4: Verify Record in Route53 Console

Double-check in Route53 console:
1. Go to **Route53 → Hosted zones → graine.ai**
2. Look for record: `sip` (Type: A, Value: 13.203.223.245)
3. Make sure it shows as **Active** (not Pending)

## Using AWS CLI

If you prefer CLI:

```bash
# Get your hosted zone ID
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones --query "HostedZones[?Name=='graine.ai.'].Id" --output text | cut -d'/' -f3)

# Create base domain record
aws route53 change-resource-record-sets \
  --hosted-zone-id $HOSTED_ZONE_ID \
  --change-batch '{
    "Changes": [{
      "Action": "UPSERT",
      "ResourceRecordSet": {
        "Name": "sip.graine.ai",
        "Type": "A",
        "TTL": 300,
        "ResourceRecords": [{"Value": "13.203.223.245"}]
      }
    }]
  }'
```

## Summary

**Current Status:**
- ✅ `*.sip.graine.ai` → 13.203.223.245 (exists)
- ❌ `sip.graine.ai` → 13.203.223.245 (missing - create this!)

**After Fix:**
- ✅ `sip.graine.ai` → 13.203.223.245 (base domain)
- ✅ `*.sip.graine.ai` → 13.203.223.245 (subdomains)

Both records are needed because wildcards don't match the base domain!

