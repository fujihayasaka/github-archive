ALTER TABLE `ts_rules` MODIFY COLUMN `repository_id` bigint(20) unsigned NOT NULL DEFAULT '0', ADD UNIQUE KEY `index_tool_id_sarif_hash` (`tool_id`,`sarif_identifier`,`hash`);
