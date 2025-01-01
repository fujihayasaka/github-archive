ALTER TABLE `ts_rules` DROP COLUMN `repository_id`, DROP KEY `index_repo_tool_id_sarif_hash`;
ALTER TABLE `ts_rule_tags`  DROP COLUMN `repository_id`;
