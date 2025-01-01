ALTER TABLE attestations DROP COLUMN tenant_id;
CREATE INDEX purl_vouchers_idx on attestations(purl);
DROP INDEX tenant_purl_attestations_idx ON attestations;
ALTER TABLE attestations MODIFY purl VARCHAR(768);
