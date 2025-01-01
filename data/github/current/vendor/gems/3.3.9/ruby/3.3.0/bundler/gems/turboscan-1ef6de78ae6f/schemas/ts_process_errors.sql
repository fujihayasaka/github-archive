CREATE TABLE `ts_process_errors` (
  `id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `repository_id` bigint unsigned NOT NULL,
  `analysis_id` bigint unsigned DEFAULT NULL,
  `error_type` tinyint unsigned NOT NULL,
  `sarif_uri` varchar(4096) COLLATE utf8mb4_general_ci NOT NULL,
  `message` varchar(4096) COLLATE utf8mb4_general_ci DEFAULT NULL,
  -- sarif_id is defined as a varchar(255) in other places. See https://github.com/github/code-scanning/issues/12627
  `sarif_id` char(36) COLLATE utf8mb4_general_ci NOT NULL DEFAULT '',
  PRIMARY KEY (`id`),
  KEY `idx_process_errors_on_repo_id_analysis_id` (`repository_id`,`analysis_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
