ALTER TABLE vouchers CHANGE subject_alias purl VARCHAR(768);
ALTER TABLE vouchers RENAME INDEX subject_alias_vouchers_idx TO purl_vouchers_idx;