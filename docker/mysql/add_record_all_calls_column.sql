-- Add record_all_calls column to accounts table
-- This column enables/disables call recording for all calls in an account

ALTER TABLE accounts 
ADD COLUMN record_all_calls BOOLEAN NOT NULL DEFAULT 0 
COMMENT 'If true, record all calls for this account';

