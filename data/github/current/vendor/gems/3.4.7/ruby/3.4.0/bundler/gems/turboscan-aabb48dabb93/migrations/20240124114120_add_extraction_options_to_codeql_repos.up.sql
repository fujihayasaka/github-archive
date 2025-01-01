ALTER TABLE `ts_codeql_repos` ADD COLUMN `java_extraction_options` tinyint unsigned DEFAULT '0', ADD COLUMN `csharp_extraction_options` tinyint unsigned DEFAULT '0';
ALTER TABLE `ts_codeql_configs` ADD COLUMN `csharp_extraction_options` tinyint unsigned DEFAULT '0';
