ALTER TABLE `ts_codeql_runs` ADD COLUMN `codeql_config_id` bigint(20) DEFAULT NULL, ADD COLUMN `run_type` tinyint(3) unsigned NOT NULL DEFAULT '0';
ALTER TABLE `ts_codeql_configs` ADD COLUMN `template_version` varchar(255) DEFAULT NULL, ADD COLUMN `tag` tinyint(3) unsigned NOT NULL DEFAULT '0', ADD COLUMN `extended_queries` tinyint(1) DEFAULT '0';
