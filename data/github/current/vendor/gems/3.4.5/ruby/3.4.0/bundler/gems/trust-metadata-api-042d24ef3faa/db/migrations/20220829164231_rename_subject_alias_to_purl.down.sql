ALTER TABLE vouchers CHANGE purl subject_alias VARCHAR(768);
ALTER TABLE vouchers RENAME INDEX purl_vouchers_idx TO subject_alias_vouchers_idx;