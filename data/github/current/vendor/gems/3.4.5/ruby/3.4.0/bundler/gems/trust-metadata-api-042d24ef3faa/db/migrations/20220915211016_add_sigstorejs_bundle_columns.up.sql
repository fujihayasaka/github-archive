ALTER TABLE attestations ADD COLUMN integrated_time INT UNSIGNED;
ALTER TABLE attestations ADD COLUMN log_id VARCHAR(255);
ALTER TABLE attestations ADD COLUMN log_index INT UNSIGNED;
ALTER TABLE attestations ADD COLUMN signed_entry_timestamp VARCHAR(255);
