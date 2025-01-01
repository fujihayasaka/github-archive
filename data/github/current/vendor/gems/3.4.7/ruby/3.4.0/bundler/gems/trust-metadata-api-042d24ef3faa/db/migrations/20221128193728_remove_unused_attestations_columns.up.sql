-- drop columns we won't use:
ALTER TABLE attestations DROP COLUMN artifact;
ALTER TABLE attestations DROP COLUMN artifact_type;
ALTER TABLE attestations DROP COLUMN integrated_time;
ALTER TABLE attestations DROP COLUMN log_id;
ALTER TABLE attestations DROP COLUMN log_index;
ALTER TABLE attestations DROP COLUMN signed_entry_timestamp;
