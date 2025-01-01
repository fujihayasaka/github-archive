ALTER TABLE attestations MODIFY COLUMN tenant_id int(10) unsigned NOT NULL;
CREATE INDEX tenant_id_purl_predicate_type_attestations_idx ON attestations (tenant_id, purl, predicate_type);