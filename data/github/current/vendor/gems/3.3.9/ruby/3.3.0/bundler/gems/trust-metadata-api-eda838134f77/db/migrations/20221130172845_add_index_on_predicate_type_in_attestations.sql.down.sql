DROP INDEX tenant_id_purl_predicate_type_attestations_idx on attestations;
CREATE INDEX tenant_purl_attestations_idx ON attestations (tenant_id, purl);

-- if we're down-migrating, what's the point of resizing the columns?
-- the up migration will just be a no-op.
