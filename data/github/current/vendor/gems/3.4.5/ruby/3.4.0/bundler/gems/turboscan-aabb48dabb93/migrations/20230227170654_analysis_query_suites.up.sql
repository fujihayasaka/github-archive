ALTER TABLE `ts_analyses` ADD COLUMN `default_queries_disabled` tinyint unsigned DEFAULT NULL;
CREATE TABLE `ts_analysis_query_suites` (
`id` bigint unsigned NOT NULL AUTO_INCREMENT,
`repository_id` bigint unsigned NOT NULL,
`analysis_id` bigint unsigned NOT NULL,
`type` tinyint unsigned NOT NULL,
`uses` varchar(1024) COLLATE utf8mb4_general_ci NOT NULL,
PRIMARY KEY (`id`),
KEY `idx_analysis_query_suites_repo_analysis` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
