-- Add missing columns to voip_carriers table
-- These columns are required by the latest Jambonz webapp

-- Add dtmf_type column (DTMF type for outbound calls)
ALTER TABLE voip_carriers 
ADD COLUMN IF NOT EXISTS dtmf_type ENUM('rfc2833','tones','info') NOT NULL DEFAULT 'rfc2833' 
COMMENT 'DTMF type for outbound calls: rfc2833 (RFC 2833), tones (in-band), or info (SIP INFO)';

-- Add outbound_sip_proxy column (optional SIP proxy for outbound calls)
ALTER TABLE voip_carriers 
ADD COLUMN IF NOT EXISTS outbound_sip_proxy VARCHAR(255) 
COMMENT 'Optional SIP proxy for outbound calls';

-- Add trunk_type column (trunk authentication type)
ALTER TABLE voip_carriers 
ADD COLUMN IF NOT EXISTS trunk_type ENUM('static_ip','auth','reg') NOT NULL DEFAULT 'static_ip' 
COMMENT 'Trunk authentication type: static_ip (IP whitelist), auth (SIP auth), or reg (SIP registration)';

