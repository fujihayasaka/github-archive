CREATE TABLE `ts_snippets` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `start_line` int unsigned NOT NULL,
  `end_line` int unsigned NOT NULL,
  `start_column` int unsigned DEFAULT NULL,
  `end_column` int unsigned DEFAULT NULL,
  `text` text COLLATE utf8mb4_general_ci NOT NULL,
  `hash` binary(32) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `idx_snippets_uniq_repo_hash` (`repository_id`,`hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
