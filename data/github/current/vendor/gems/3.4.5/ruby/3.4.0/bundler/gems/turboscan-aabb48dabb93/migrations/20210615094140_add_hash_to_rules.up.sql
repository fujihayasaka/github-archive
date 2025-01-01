ALTER TABLE `ts_rules` ADD COLUMN `hash` binary(32), DROP KEY `index_repo_tool_id_sarif`, ADD UNIQUE KEY `index_repo_tool_id_sarif_hash` (`repository_id`,`tool_id`,`sarif_identifier`,`hash`);
