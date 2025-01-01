ALTER TABLE `ts_codeql_configs` ADD COLUMN `cpp_extraction_options` tinyint unsigned DEFAULT '0';
ALTER TABLE `ts_codeql_repos` ADD COLUMN `cpp_extraction_options` tinyint unsigned DEFAULT '0';
