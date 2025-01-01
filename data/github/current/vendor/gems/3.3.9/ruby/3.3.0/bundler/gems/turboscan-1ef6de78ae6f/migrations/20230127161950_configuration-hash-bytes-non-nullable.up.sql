ALTER TABLE `ts_analyses` MODIFY COLUMN `configuration_hash_bytes` binary(32) NOT NULL, ADD UNIQUE KEY `idx_analyses_configuration_most_recent` (`configuration_hash_bytes`,`unique_most_recent`);
