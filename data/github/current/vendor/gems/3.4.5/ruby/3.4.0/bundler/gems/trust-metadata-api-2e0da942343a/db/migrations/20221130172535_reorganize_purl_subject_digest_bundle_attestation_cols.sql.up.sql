-- reorganize columns, because of pedantic aesthetics:
-- it makes the attestations.sql dump nicer to read

ALTER TABLE attestations CHANGE COLUMN purl purl VARCHAR(767) AFTER id;
ALTER TABLE attestations CHANGE COLUMN subject_digest subject_digest VARCHAR(255) NOT NULL AFTER purl;
ALTER TABLE attestations CHANGE COLUMN bundle bundle longtext NOT NULL AFTER media_type;

