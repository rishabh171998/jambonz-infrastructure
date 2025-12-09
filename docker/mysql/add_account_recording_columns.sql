-- Add missing columns to accounts table for call recording functionality
-- These columns are required by newer versions of jambonz webapp

USE jambones;

-- Add record_format column (if not exists)
ALTER TABLE accounts 
ADD COLUMN record_format VARCHAR(16) NOT NULL DEFAULT 'mp3' 
COMMENT 'Audio format for call recordings (mp3, wav, etc.)';

-- Add bucket_credential column (if not exists)
ALTER TABLE accounts 
ADD COLUMN bucket_credential VARCHAR(8192) 
COMMENT 'credential used to authenticate with storage service';

-- Add enable_debug_log column (if not exists)
ALTER TABLE accounts 
ADD COLUMN enable_debug_log BOOLEAN NOT NULL DEFAULT false 
COMMENT 'Enable debug logging for calls in this account';

