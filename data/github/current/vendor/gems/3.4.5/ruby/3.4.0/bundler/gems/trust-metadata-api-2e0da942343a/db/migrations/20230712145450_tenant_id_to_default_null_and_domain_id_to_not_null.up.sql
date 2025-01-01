ALTER TABLE attestations MODIFY COLUMN tenant_id int unsigned DEFAULT NULL;
ALTER TABLE attestations MODIFY COLUMN domain_id int unsigned NOT NULL;