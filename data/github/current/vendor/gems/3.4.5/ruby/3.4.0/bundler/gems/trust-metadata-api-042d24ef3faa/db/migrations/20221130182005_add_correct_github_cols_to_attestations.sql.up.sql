ALTER TABLE attestations ADD COLUMN owner_id bigint(20) AFTER purl;
ALTER TABLE attestations ADD COLUMN repository_id bigint(20) after owner_id;
