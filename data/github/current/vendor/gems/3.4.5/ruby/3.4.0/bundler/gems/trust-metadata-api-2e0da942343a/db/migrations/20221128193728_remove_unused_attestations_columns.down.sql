ALTER TABLE attestations ADD COLUMN artifact longblob NOT NULL;
ALTER TABLE attestations ADD COLUMN artifact_type varchar(4096) NOT NULL;
ALTER TABLE attestations ADD COLUMN integrated_time bigint(20) unsigned NOT NULL;
ALTER TABLE attestations ADD COLUMN log_id varbinary(255);
ALTER TABLE attestations ADD COLUMN log_index bigint(20) unsigned NOT NULL;
ALTER TABLE attestations ADD COLUMN signed_entry_timestamp varbinary(255) NOT NULL;
