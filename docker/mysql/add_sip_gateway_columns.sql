-- Add missing columns to sip_gateways table
-- These columns are required by the latest Jambonz webapp

-- Add protocol column (SIP transport protocol)
ALTER TABLE sip_gateways 
ADD COLUMN IF NOT EXISTS protocol ENUM('udp','tcp','tls', 'tls/srtp') DEFAULT 'udp' 
COMMENT 'Outbound call protocol';

-- Add send_options_ping column (send OPTIONS ping to keep connection alive)
ALTER TABLE sip_gateways 
ADD COLUMN IF NOT EXISTS send_options_ping BOOLEAN NOT NULL DEFAULT 0;

-- Add use_sips_scheme column (use sips:// scheme for TLS)
ALTER TABLE sip_gateways 
ADD COLUMN IF NOT EXISTS use_sips_scheme BOOLEAN NOT NULL DEFAULT 0;

-- Add pad_crypto column (P-Asserted-Identity crypto)
ALTER TABLE sip_gateways 
ADD COLUMN IF NOT EXISTS pad_crypto BOOLEAN NOT NULL DEFAULT 0;

