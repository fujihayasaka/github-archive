ALTER TABLE attestations ADD COLUMN signer varchar(512) COLLATE utf8mb4_unicode_ci DEFAULT NULL;
DROP INDEX domain_id_owner_id_repository_id_predicate_type_attestations_idx ON attestations;
CREATE INDEX domain_id_owner_id_repository_id_predicate_type_attestations_idx ON attestations (domain_id, owner_id, repository_id, predicate_type, signer);
