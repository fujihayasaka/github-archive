ALTER TABLE vouchers ADD COLUMN subject_alias VARCHAR(768);
CREATE INDEX subject_alias_vouchers_idx ON vouchers (subject_alias);
