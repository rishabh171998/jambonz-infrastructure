-- Migration script to add pad_crypto column to sip_gateways table
-- This column is required by newer versions of jambonz sbc-inbound application

USE jambones;

-- Check if column exists, if not add it
-- Note: This will fail if column already exists, which is fine
ALTER TABLE sip_gateways 
ADD COLUMN pad_crypto BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'P-Asserted-Identity crypto flag';

