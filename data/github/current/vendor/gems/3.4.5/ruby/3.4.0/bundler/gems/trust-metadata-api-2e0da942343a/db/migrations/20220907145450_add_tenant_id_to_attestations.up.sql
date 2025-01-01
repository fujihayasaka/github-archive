ALTER TABLE attestations ADD COLUMN tenant_id int unsigned FIRST;
DROP INDEX purl_vouchers_idx on attestations;
-- mysql max key length is 3072 bytes, so we can't have a composite key unless
-- we reduce the max purl size by sizeof(tenant_id) (i.e. 4 bytes).
-- before, it was 768 4-byte chars, so now it's:
ALTER TABLE attestations MODIFY purl VARCHAR(767);
CREATE INDEX tenant_purl_attestations_idx ON attestations (tenant_id, purl);
