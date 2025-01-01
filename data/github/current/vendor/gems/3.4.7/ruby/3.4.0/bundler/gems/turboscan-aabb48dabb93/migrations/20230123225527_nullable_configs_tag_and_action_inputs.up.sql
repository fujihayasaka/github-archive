ALTER TABLE `ts_codeql_runs` ADD COLUMN `action_inputs` json DEFAULT NULL;
ALTER TABLE `ts_codeql_configs` MODIFY COLUMN `tag` tinyint(3) unsigned DEFAULT NULL;
