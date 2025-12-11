-- Create clients table for SIP user registration

CREATE TABLE IF NOT EXISTS clients (
  client_sid CHAR(36) NOT NULL UNIQUE,
  account_sid CHAR(36) NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT 1,
  username VARCHAR(64),
  password VARCHAR(1024),
  allow_direct_app_calling BOOLEAN NOT NULL DEFAULT 1,
  allow_direct_queue_calling BOOLEAN NOT NULL DEFAULT 1,
  allow_direct_user_calling BOOLEAN NOT NULL DEFAULT 1,
  PRIMARY KEY (client_sid),
  INDEX account_sid_idx (account_sid),
  INDEX username_idx (username),
  FOREIGN KEY (account_sid) REFERENCES accounts(account_sid)
) COMMENT='SIP clients/users that can register to an account';

