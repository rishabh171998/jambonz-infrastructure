-- Add missing lcr table
-- This table is required for LCR (Least Cost Routing) functionality

CREATE TABLE IF NOT EXISTS lcr
(
  lcr_sid CHAR(36) NOT NULL UNIQUE,
  name VARCHAR(64) COMMENT 'User-assigned name for this LCR table',
  is_active BOOLEAN NOT NULL DEFAULT 1,
  default_carrier_set_entry_sid CHAR(36) COMMENT 'default carrier/route to use when no digit match based results are found.',
  service_provider_sid CHAR(36),
  account_sid CHAR(36),
  PRIMARY KEY (lcr_sid)
) COMMENT='An LCR (least cost routing) table that is used by a service provider';

-- Create indexes
CREATE INDEX IF NOT EXISTS lcr_sid_idx ON lcr (lcr_sid);
CREATE INDEX IF NOT EXISTS service_provider_sid_idx ON lcr (service_provider_sid);
CREATE INDEX IF NOT EXISTS account_sid_idx ON lcr (account_sid);

-- Add foreign key constraint for default_carrier_set_entry_sid
ALTER TABLE lcr 
ADD CONSTRAINT default_carrier_set_entry_sid_idxfk 
FOREIGN KEY (default_carrier_set_entry_sid) 
REFERENCES lcr_carrier_set_entry (lcr_carrier_set_entry_sid);

