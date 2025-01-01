ALTER TABLE `ts_rules` ADD COLUMN `tool_id` bigint(20) unsigned DEFAULT NULL;
ALTER TABLE `ts_analyses` ADD COLUMN `tool_version_id` bigint(20) unsigned DEFAULT NULL;
