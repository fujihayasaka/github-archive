CREATE TABLE `autofix_suggestion_jobs` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `pull_request_id` bigint NOT NULL,
  `target_sha` varchar(40) COLLATE utf8mb4_general_ci NOT NULL,
  `rule_sarif_identifier` varchar(255) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `sarif_content` json DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) NOT NULL,
  `check_run_id` bigint DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `index_autofix_suggestion_jobs_on_pull_request_and_sha` (`pull_request_id`,`target_sha`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;
