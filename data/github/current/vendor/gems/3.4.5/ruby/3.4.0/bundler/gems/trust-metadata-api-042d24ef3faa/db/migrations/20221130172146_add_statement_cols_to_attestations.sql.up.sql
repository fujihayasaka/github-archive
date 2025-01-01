ALTER TABLE attestations ADD COLUMN statement_type varchar(255) NOT NULL;
ALTER TABLE attestations ADD COLUMN statement LONGTEXT NOT NULL;
