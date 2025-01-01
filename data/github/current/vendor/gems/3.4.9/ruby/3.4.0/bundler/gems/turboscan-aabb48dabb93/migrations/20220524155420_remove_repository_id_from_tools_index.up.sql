ALTER TABLE `ts_tools` MODIFY COLUMN `repository_id` bigint(20) unsigned NOT NULL DEFAULT '0', ADD UNIQUE KEY `index_guid` (`guid`), ADD KEY `index_canonical_name` (`canonical_name`);
ALTER TABLE `ts_tool_versions` MODIFY COLUMN `repository_id` bigint(20) unsigned NOT NULL DEFAULT '0';
