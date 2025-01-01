ALTER TABLE attestations
ADD COLUMN subject_digest VARCHAR(255),
ADD COLUMN subject_name VARCHAR(512);
