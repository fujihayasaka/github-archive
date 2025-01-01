ALTER TABLE attestations MODIFY COLUMN integrated_time INT UNSIGNED;
ALTER TABLE attestations MODIFY COLUMN log_id VARCHAR(255);
ALTER TABLE attestations MODIFY COLUMN log_index INT UNSIGNED;
ALTER TABLE attestations MODIFY COLUMN signed_entry_timestamp VARCHAR(255);
