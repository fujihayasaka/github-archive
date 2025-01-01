DROP INDEX tenant_id_purl_predicate_type_attestations_idx on attestations;
CREATE UNIQUE INDEX tenant_id_purl_predicate_type_attestations_idx ON attestations (tenant_id, purl, predicate_type);
