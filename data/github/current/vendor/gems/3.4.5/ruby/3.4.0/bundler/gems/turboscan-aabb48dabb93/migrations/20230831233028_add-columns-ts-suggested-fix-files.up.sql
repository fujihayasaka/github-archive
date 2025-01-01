ALTER TABLE `ts_suggested_fix_files` ADD COLUMN `file_path_hash` binary(32) DEFAULT NULL, ADD COLUMN `file_checksum` binary(20) DEFAULT NULL;
