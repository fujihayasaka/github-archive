ALTER TABLE `ts_codeql_repos` ADD COLUMN `runner_label` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL;
ALTER TABLE `ts_codeql_configs` ADD COLUMN `runner_label` varchar(256) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci DEFAULT NULL;
